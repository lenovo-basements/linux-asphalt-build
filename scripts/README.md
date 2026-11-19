# Building asphalt images

How the pieces fit, in build order. Nothing here flashes anything: flashing is
always a manual step (see the end).

| step | script | runs on | produces |
|---|---|---|---|
| 1 | (one-time) build host | Mac or Linux | an aarch64 Arch Linux ARM chroot |
| 2 | `build-packages.sh` | ALARM (chroot or tablet), root | `pkgbuilds/out/*.pkg.tar.*` |
| 3 | `kernel/build-kernel.sh` | Mac or Linux | `Image`, modules, DTBs, `boot.img` + `vendor_boot.img` |
| 4 | `build-rootfs.sh` | ALARM (chroot or tablet), root | a populated root filesystem tree |
| 5 | `mkfs.ext4 -d` | Linux | `asphalt-root.img` |

Order matters a little: `linux-asphalt` (step 2) wraps a kernel build (step 3),
and `build-rootfs.sh` installs whatever is in `pkgbuilds/out/`.

Expected layout: the repos side by side.

```
<work>/
  linux-asphalt-build/   this repo
  asphalt-firmware/      firmware + sensor/audio configs (asphalt-firmware package)
  mainline/              kernel tree with the asphalt patches
```

## 1. Build host

The packages and the rootfs are built **on aarch64 Arch Linux ARM**: either the
tablet itself, or a clean ALARM chroot. On a Mac, use a Lima VM (Apple
Virtualization, aarch64, so no emulation):

```sh
limactl create --name asphalt --vm-type vz --cpus 6 --memory 8 --disk 40 template:ubuntu
limactl start asphalt
# inside the VM: unpack ArchLinuxARM-aarch64-latest.tar.gz to /srv/alarm, then
sudo mount --bind /srv/alarm /srv/alarm          # pacman wants a mount point
sudo mkdir -p /srv/alarm/<work>
sudo mount --bind <work> /srv/alarm/<work>        # the repos, inside the chroot
sudo arch-chroot /srv/alarm
```

The two bind mounts are lost when the VM stops; redo them after each start.
In the chroot: `pacman-key --init && pacman-key --populate archlinuxarm`, then
`pacman -Syu base-devel git`. If `mirror.archlinuxarm.org` stalls, uncomment
other mirrors in `/etc/pacman.d/mirrorlist`.

the build process might be differ on linux, this rootfs build against macos 27.3 (golden gate), on macbook pro m1,
this build process hasn't tested on native linux (asahi linux, or amd64 linux) yet. so might be differs.

## 2. Packages: `build-packages.sh`

Builds `pkgbuilds/*` in dependency order and collects them in `pkgbuilds/out/`.
Runs as root; `makepkg` runs as `$BUILD_USER` (default `asphalt-build`, created
if needed). Packaged straight from the local checkouts, e.g. asphalt-firmware
from `../asphalt-firmware` (`ASPHALT_FIRMWARE_DIR` overrides).

```sh
cd <work>/linux-asphalt-build
sudo scripts/build-packages.sh                          # everything except linux-asphalt
sudo scripts/build-packages.sh asphalt-device-support   # just one (or a few)
sudo scripts/build-packages.sh --kernel <artifacts> linux-asphalt   # after step 3
```

- Version numbers come from git (`r<count>.g<hash>`), so **commit first**:
  uncommitted changes build under the previous version number.
- `linux-asphalt` is built only with `--kernel <build-kernel.sh artifacts dir>`;
  it packages that build's modules (its version is the kernel release).
- See [pkgbuilds packages](../pkgbuilds/README.md) for what each package is.

## 3. Kernel

`build-kernel.sh` builds the arm64 `Image`, modules and the asphalt (ROW) DTB from a
kernel tree, then repackages flashable `boot.img` + `vendor_boot.img`.
It never flashes anything.

```sh
scripts/kernel/build-kernel.sh \
    --src ~/linux \
    --out /tmp/asphalt-build \
    --artifacts ./out/my-build \
    --baseline ~/asphalt-baseline \
    --localversion -asphalt
```

| Option | Meaning |
| --- | --- |
| `--src` | Kernel source tree with the asphalt patches. |
| `--out` | Kernel build directory (`O=`). Must already contain a `.config`. |
| `--artifacts` | Where the results go (see below). |
| `--baseline` | Packaging baseline (see below). |
| `--localversion` | Optional `CONFIG_LOCALVERSION`. Use a new one per experiment so its modules don't overwrite the running kernel's. |
| `--fragment` | Allow to make fragment config to merge with main kernel config, for experimenting or improving the kernel without need to modify kernel config, Values that did not survive are listed in `<artifacts>/fragments/not-applied.txt`. |
| `--allow-compatible` | The exact root compatible packaging accepts although it differs from the baseline (space-separated). Defaults to the asphalt ROW list, rename. msm-id, board-id and region_country always have to match. |
| `--firmware-dir` | asphalt-firmware checkout (default: next to linux-asphalt-build). The baseline boot ramdisk carries the firmware the DSPs and GPU zap load before the root is mounted, still under the pre-rename names; packaging renames it (`package-boot.py --rename-firmware`) and checks every renamed file is byte-identical to this tree. The audio topology is not renamed: the sound card loads it from the rootfs, after root is mounted (built from `audio/Lenovo-Asphalt.m4` with `audio/build-topology.sh`), for first timers, this isn't needed. |
| `-j` | Parallel jobs (default: all CPUs). |

`package-boot.py` also takes `--kernel-compression {none,lz4,gz}` (default
`none`): the kernel is stored in boot.img as legacy-frame LZ4 or gzip, 
however, bootloader give middle finger on lz4 (neither legacy),
as it straight to crashdump with error code 669

### Host requirements

- **Linux:** `make`, LLVM/clang and lld (the build uses `LLVM=1`), `python3`,
  plus `lz4` for packaging. Native arm64 or cross from x86_64 both work.
- **macOS:** Homebrew `llvm`, `lld`, `make` (`gmake`), `gnu-sed`, `coreutils`,
  `lz4`. The headers in `host-compat/` let the kernel's host tools (modpost,
  gen_init_cpio, ...) build against Darwin's libc. The source tree must be on a
  case-sensitive volume.

### Output

```
<artifacts>/
  Image  kernel.config  kernel.release
  sm8475-lenovo-asphalt-row.dtb        upstream DTB
  sm8475-lenovo-asphalt-row-abl.dtb    + asphalt-abl.dtso (what Lenovo's ABL needs)
  modules.tar.gz                   extract on the tablet with: tar -xzf ... -C /
  source.commit  source.patch      exact source used
  flash/boot.img  flash/vendor_boot.img  flash/SHA256SUMS  flash/manifest.json
```

Install the modules before flashing, then run `depmod <kernel.release>`.
Arch Linux ARM has `/lib -> usr/lib`, so the archive ships `usr/lib/modules`;
use `tar --keep-directory-symlink` if your tar would otherwise replace the link.

## 4. Root filesystem: `build-rootfs.sh`

Builds a complete Arch Linux ARM root into a directory (or a mounted
partition), installs **every package in `pkgbuilds/out/`**, then the desktop
you choose. Run as root on ALARM (the chroot from step 1).

```sh
sudo scripts/build-rootfs.sh --target /srv/rootfs \
    --user <name> --shell /usr/bin/fish --hostname asphalt --timezone Asia/Bangkok \
    --desktop hyprland --greeter /path/to/greeter-installer \
    --extra-packages my-packages.txt --ssh-key ~/.ssh/id_ed25519.pub
```

| Option | Meaning |
| --- | --- |
| `--target` | Rootfs directory (required). |
| `--user`, `--password` | Primary user (default `alarm`, password = user name). Change it on first login. |
| `--hostname`, `--timezone` | Defaults `asphalt`, `UTC`. The PMIC RTC can't be set from Linux, so `systemd-timesyncd` is always enabled. |
| `--desktop` | `none` (default: console login), `hyprland`, or `gnome`. |
| `--greeter` | hyprland: run this greeter installer instead of autologin. It is called as `bash <script> --root <target> --user <name>` and must set up greetd in that root. |
| `--no-autologin` | Desktops: ask for a login. |
| `--extra-packages` | A file of extra package names (whitespace-separated, `#` comments). |
| `--shell`, `--ssh-key` | Login shell; `--ssh-key` enables sshd, key-only, with that authorized_keys file. |
| `--tarball`, `--firmware-dir` | Reuse a downloaded ALARM tarball; asphalt-firmware location. |

Always enabled: NetworkManager, Bluetooth, timesyncd, and the device preset
from `asphalt-device-support` (sensors, lid, power button, Wi-Fi MAC, haptics,
USB networking gadget, etc.).

**`pkgbuilds/out/` is the install list**: remove packages you don't want in the
image (old builds, or ones like a private package) before running this.

## 5. Image

```sh
mkfs.ext4 -L asphalt-arch -U <uuid> -E root_owner=0:0 -d /srv/rootfs asphalt-root.img <size>
```

- The label must match the root entry in the image's `/etc/fstab`
  (`LABEL=asphalt-arch`); the UUID must be the `ROOT_UUID` the boot.img's
  init looks for.
- `x-systemd.growfs` in fstab grows it to the whole partition on first boot,
  so the image only needs to fit the files.

## 6. Flashing (manual)

With the tablet in fastboot:

```sh
fastboot flash boot_b     <artifacts>/flash/boot.img
fastboot flash vendor_boot_b <artifacts>/flash/vendor_boot.img
fastboot --set-active=b && fastboot reboot
```

- **A new kernel release needs its modules on the tablet before it boots**
  (Wi-Fi is a module): install the `linux-asphalt` package, or copy
  `modules-root/usr/lib/modules/<release>` over (`rsync`, not macOS `tar`,
  which adds `._*` files), then `depmod <release>`.
- A DT-only change keeps the release: only `vendor_boot.img` changes.
- Keep `flash/boot-recovery.img` + `vendor_boot-recovery.img` (the baseline
  pair) at hand to get back.
- The root filesystem image is too big for one fastboot download: write it from
  recovery (`adb` + `dd` to `/dev/block/by-name/<partition>`) or as a sparse
  image (`img2simg`).
- the script doesn't have automated image flashing, user **must** do it yourself,
  to avoid catastrophic error that will waste user time to restore with EDL package.

## Other scripts

- `install-device-support.sh`: the pre-package way to copy `rootfs/` into a
  target (used by `build-rootfs.sh` only when no packages are in
  `pkgbuilds/out/`). Prefer the `asphalt-device-support` package.
- `get_pkgs.py`: downloads a few networking packages (iwd, wpa_supplicant,
  wireless-regdb, etc.) from the Arch mirrors for offline installs.
