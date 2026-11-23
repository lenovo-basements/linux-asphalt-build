# Building asphalt images

This is the whole path from a stock tablet to Arch Linux ARM booting on it.
Nothing here flashes anything: flashing is always a manual step (the end), so
a typo in a script can't brick your tablet. A typo in a `fastboot` command still can.

If this is your first time, read [Before you start](#before-you-start) and then
follow [the first build](#first-build-the-short-version) top to bottom. The
numbered sections after that explain each step and their options.

- [Before you start](#before-you-start)
- [The first build, the short version](#first-build-the-short-version)
- [0. Sources and a packaging baseline](#0-sources-and-a-packaging-baseline)
- [1. Build host](#1-build-host)
- [2. Kernel](#2-kernel)
- [3. Packages](#3-packages-build-packagessh)
- [4. Root filesystem](#4-root-filesystem-build-rootfssh)
- [5. Image, and where root lives](#5-image)
- [6. Flashing (manual)](#6-flashing-manual)
- [Troubleshooting](#troubleshooting)

## Before you start

You need all of these. Don't skip the backup one.

- [ ] A **Lenovo Legion Y700 (2023), TB320FC** with an **unlocked bootloader**.
      This tree targets the ROW (global) model. A PRC (国行) tablet uses the same
      DTB but different camera modules, and the maintainer hasn't tested it. Reports are welcome.
- [ ] **Backups of `persist`, `sn` and `devinfo`**, kept off the tablet. They are
      unique to your tablet and you can't borrow them from someone else (see
      [Persist](../README.md#technical-notes)). From a recovery with root adb, for example Lineage recovery:
      ```sh
      adb pull /dev/block/by-name/persist persist.img
      adb pull /dev/block/by-name/sn sn.img
      adb pull /dev/block/by-name/devinfo devinfo.img
      ```
- [ ] An **Apple Silicon Mac** (what the maintainer uses) **or a Linux machine**.
      Building on Linux should work but nobody has tested it end to end yet.
- [ ] `fastboot` and `adb` (Android platform-tools).
- [ ] **Somewhere for the root filesystem to live**. A **microSD card** is the
      easy choice and needs no repartitioning. A UFS partition is the advanced
      choice. See [where root lives](#where-root-lives).
- [ ] A **packaging baseline** (a known-good asphalt boot image pair). See
      [step 0](#0-sources-and-a-packaging-baseline). You can't build without one.

Linux goes on **slot B**. Android stays on slot A, and
`fastboot --set-active=a && fastboot reboot` always takes you back.

## First build, the short version

`<work>` is any directory. On a Mac it must be on a **case-sensitive** volume
(see [host requirements](#host-requirements)).

```sh
# on the Mac / Linux host
cd <work>
git clone https://github.com/lenovo-basements/linux-asphalt-build
git clone https://github.com/lenovo-basements/asphalt-firmware
git clone --depth 1 https://github.com/lenovo-basements/lenovo-sm8475-mainline mainline
# put the baseline (step 0) in <work>/baseline and check it:
(cd baseline && shasum -a 256 -c SHA256SUMS)

# 2. kernel (host)
linux-asphalt-build/scripts/kernel/build-kernel.sh \
    --src mainline --out <work>/kbuild --artifacts <work>/out/first \
    --baseline <work>/baseline --defconfig y700.config
grep -m1 '^ROOT_UUID=' out/first/flash/init   # remember this UUID for step 5

# 3-5. inside the ALARM chroot (step 1), with <work> mounted at the same path
cd <work>/linux-asphalt-build
sudo scripts/build-packages.sh --kernel <work>/out/first linux-asphalt
sudo scripts/build-packages.sh
sudo scripts/build-rootfs.sh --target /srv/rootfs --user <name> --desktop hyprland
mkfs.ext4 -L asphalt-arch -U <ROOT_UUID> -E root_owner=0:0 \
    -d /srv/rootfs <work>/asphalt-root.img 8G

# 5. write asphalt-root.img to a microSD partition (see "where root lives")
# 6. flash, tablet in fastboot (host)
fastboot flash boot_b        out/first/flash/boot.img
fastboot flash vendor_boot_b out/first/flash/vendor_boot.img
fastboot --set-active=b && fastboot reboot
```

Log in as `<name>` with the password `<name>`, then **change it** with `passwd`.

| step | script | runs on | produces |
|---|---|---|---|
| 0 | `git clone` + baseline | host | the three repos, `baseline/` |
| 1 | (one-time) build host | Mac or Linux | an aarch64 Arch Linux ARM chroot |
| 2 | `kernel/build-kernel.sh` | Mac or Linux | `Image`, modules, DTBs, `boot.img` + `vendor_boot.img` |
| 3 | `build-packages.sh` | ALARM (chroot or tablet), root | `pkgbuilds/out/*.pkg.tar.*` |
| 4 | `build-rootfs.sh` | ALARM (chroot or tablet), root | a populated root filesystem tree |
| 5 | `mkfs.ext4 -d` | ALARM chroot or Linux | `asphalt-root.img` |
| 6 | `fastboot` (by hand) | host | a tablet that boots Linux on slot B |

The kernel comes before the packages because `linux-asphalt`, the package
that carries the kernel modules, is made from a kernel build. Without it the
image has no modules, so no Wi-Fi, no audio and not much else.

Expected layout, with the repos side by side:

```
<work>/
  linux-asphalt-build/   this repo
  asphalt-firmware/      firmware + sensor/audio configs (asphalt-firmware package)
  mainline/              kernel tree with the asphalt patches (lenovo-sm8475-mainline)
  baseline/              packaging baseline (step 0)
```

## 0. Sources and a packaging baseline

The kernel is the [lenovo-sm8475-mainline](https://github.com/lenovo-basements/lenovo-sm8475-mainline)
tree. `--depth 1` saves you several GB of Linux history. The firmware lives in
[asphalt-firmware](https://github.com/lenovo-basements/asphalt-firmware), and
`build-kernel.sh` and `build-packages.sh` look for it next to this repo.

### Packaging baseline

`build-kernel.sh` doesn't build a boot image from scratch. It takes an
existing asphalt `boot.img` + `vendor_boot.img` (the **baseline**) and swaps
in your new kernel and DTB. It keeps the baseline's boot ramdisk, which holds the
small loader (`/init`, the same as [`initramfs/init`](../initramfs/init)) that
finds and mounts the root filesystem, plus the early firmware. It also saves
copies of the baseline pair as `boot-recovery.img` / `vendor_boot-recovery.img`
so you can go back.

#### First-time setup

A **stock** `boot.img` won't work: it has no asphalt loader. There is no
script yet to make a baseline from stock images.

1. Download the maintainer's baseline:
   [Google Drive folder](https://drive.google.com/drive/folders/1m4dMdG6Tgw29iaa3FZh0e9Jd-EAKGybT?usp=sharing)
   (from [issue #1](https://github.com/lenovo-basements/linux-asphalt-build/issues/1)).
   It is built for the ROW tablet.
2. Put the files in `<work>/baseline/`. The directory must contain these:

   | file | what |
   |---|---|
   | `boot.img`, `vendor_boot.img` | the pair, from the same build, Android boot header v4 |
   | `dtbo.img` (or `dtbo-retained.img`) | a record of the DTBO that goes with the pair. It is never flashed |
   | `kernel.release` | the baseline's kernel release, one line |
   | `SHA256SUMS` | checksums of the two boot images and the DTBO, bare filenames |

   If the download has only the three `.img` files, create the other two:
   ```sh
   cd <work>/baseline
   # the kernel in boot.img is stored uncompressed, so its version string is readable
   LC_ALL=C grep -a -o -m1 'Linux version [^ ]*' boot.img | cut -d' ' -f3 > kernel.release
   shasum -a 256 boot.img vendor_boot.img dtbo.img > SHA256SUMS
   ```
3. Check the baseline with `shasum -a 256 -c SHA256SUMS`. Every line should say `OK`.
4. Pass that directory as `--baseline`. The loader in this baseline looks for
   the root filesystem by `ROOT_UUID`. After your first kernel build, run
   `grep -m1 '^ROOT_UUID=' <artifacts>/flash/init` to read it, or look in
   `flash/manifest.json` under `loader.identity.ROOT_UUID`. Your root image
   must use that UUID ([step 5](#5-image)).

#### Subsequent builds

Point `--baseline` at the `flash/` directory of a build that has already
booted on your tablet. That directory already has everything listed above, and its
loader already points at your root filesystem.

## 1. Build host

The packages and the rootfs are built **on aarch64 Arch Linux ARM**: either the
tablet itself, or a clean ALARM chroot. On a Mac, use a [Lima](https://lima-vm.io)
VM (`brew install lima`). It uses Apple Virtualization on aarch64, so there's no emulation.
`<work>` has to be mounted **writable** in the VM. Lima's default home mount is read-only.

```sh
limactl create --name asphalt --vm-type vz --cpus 6 --memory 8 --disk 40 \
    --mount <work>:w template:ubuntu
limactl start asphalt
limactl shell asphalt
# inside the VM:
curl -LO http://mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
sudo apt install arch-install-scripts libarchive-tools     # arch-chroot, bsdtar
sudo mkdir -p /srv/alarm && sudo bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C /srv/alarm
sudo mount --bind /srv/alarm /srv/alarm          # pacman wants a mount point
sudo mkdir -p /srv/alarm<work>
sudo mount --bind <work> /srv/alarm<work>        # the repos, at the same path inside the chroot
sudo arch-chroot /srv/alarm
```

(`--mount` needs Lima 1.0 or later. On older versions, edit the `mounts:` list
with `limactl edit asphalt`.)

The two bind mounts are lost when the VM stops, so redo them after each start.
The first time in the chroot, run
`pacman-key --init && pacman-key --populate archlinuxarm`, then
`pacman -Syu base-devel git`. If `mirror.archlinuxarm.org` stalls, uncomment
other mirrors in `/etc/pacman.d/mirrorlist`.

Mounting `<work>` at the same path inside the chroot means paths like
`<work>/out/first` work on both sides.

This rootfs is built on macOS 27.3 (Golden Gate) on a MacBook Pro M1. Nobody has
tested the build on native Linux yet (Asahi Linux or amd64 Linux), so the steps
there might be a bit different.

## 2. Kernel

`build-kernel.sh` builds the arm64 `Image`, the modules and the asphalt (ROW) DTB from a
kernel tree, then repackages a flashable `boot.img` + `vendor_boot.img` from the
[baseline](#packaging-baseline). It never flashes anything.

```sh
scripts/kernel/build-kernel.sh \
    --src <work>/mainline \
    --out <work>/kbuild \
    --artifacts <work>/out/my-build \
    --baseline <work>/baseline \
    --defconfig y700.config \
    --localversion -asphalt
```

The last lines of a good build are `BUILD-OK <release>` and `PACKAGE-OK <dir>`.

| Option | Meaning |
| --- | --- |
| `--src` | Kernel source tree with the asphalt patches. |
| `--out` | Kernel build directory (`O=`). Reuse it between builds: incremental builds are much faster. |
| `--defconfig` | First build only: when `--out` has no `.config` yet, generate one with this config target from the kernel tree (`y700.config` = `arch/arm64/configs/y700.config`). An existing `.config` is never overwritten. |
| `--artifacts` | Where the results go (see below). |
| `--baseline` | Required directory with a [known-good boot image pair](#packaging-baseline). |
| `--localversion` | Optional `CONFIG_LOCALVERSION`. Use a new one per experiment so its modules don't overwrite the running kernel's. |
| `--fragment` | Allow to make fragment config to merge with main kernel config, for experimenting or improving the kernel without need to modify kernel config, Values that did not survive are listed in `<artifacts>/fragments/not-applied.txt`. |
| `--allow-compatible` | The exact root compatible packaging accepts although it differs from the baseline (space-separated). Defaults to the asphalt ROW list, rename. msm-id, board-id and region_country always have to match. |
| `--firmware-dir` | asphalt-firmware checkout (default: next to linux-asphalt-build). If the baseline ramdisk still uses `qcom/lenovo/tb320fc`, packaging renames those paths to `qcom/lenovo/asphalt` and checks the renamed files against this checkout. If the ramdisk already uses the new paths, the rename is skipped. |
| `-j` | Parallel jobs (default: all CPUs). |

`package-boot.py` also takes `--kernel-compression {none,lz4,gz}` (default
`none`): the kernel is stored in boot.img as legacy-frame LZ4 or gzip,
however, bootloader give middle finger on lz4 (neither legacy),
as it straight to crashdump with error code 669

### Host requirements

- **Linux:** `make`, LLVM/clang and lld (the build uses `LLVM=1`), `python3`,
  plus `lz4` for packaging. Native arm64 or cross from x86_64 both work.
- **macOS:** Homebrew `llvm`, `lld`, `make` (`gmake`), `gnu-sed`, `coreutils`,
  `lz4`, plus `android-platform-tools` for fastboot/adb:
  ```sh
  brew install llvm lld make gnu-sed coreutils lz4
  brew install --cask android-platform-tools
  ```
  The headers in `host-compat/` let the kernel's host tools (modpost,
  gen_init_cpio, ...) build against Darwin's libc. **The kernel source tree must be on a
  case-sensitive volume**, because the default APFS volume is not case-sensitive. You can add one
  without repartitioning (find your container with `diskutil list`, usually `disk3`):
  ```sh
  diskutil apfs addVolume disk3 "Case-sensitive APFS" linux    # shows up at /Volumes/linux
  ```
- **Rust (both):** optional. `CONFIG_RUST` (for the Rust binder that Waydroid
  needs) wants rustc with the `rust-src` component and `bindgen`, and
  `make rustavailable` checks for them. Without them, the build still works and silently leaves
  Rust (and so Waydroid's binder) out. With CFI on, rustc's LLVM should match clang's major version.
  On macOS, use Homebrew `rustup` (keg-only, picked up by build-kernel.sh) and
  `bindgen`, then `rustup toolchain install stable --profile minimal
  --component rust-src`.

### Output

```
<artifacts>/
  Image  kernel.config  kernel.release
  sm8475-lenovo-asphalt-row.dtb        upstream DTB
  sm8475-lenovo-asphalt-row-abl.dtb    + asphalt-abl.dtso (what Lenovo's ABL needs)
  modules.tar.gz                   usr/lib/modules/<release>, see "Installing a new kernel"
  source.commit  source.patch      exact source used
  package.log                      packaging report (attach it to bug reports)
  flash/boot.img  flash/vendor_boot.img       what you flash
  flash/boot-recovery.img  flash/vendor_boot-recovery.img   the baseline pair, to go back
  flash/init  flash/manifest.json  flash/FLASHING.txt  flash/SHA256SUMS
```

## 3. Packages: `build-packages.sh`

Builds `pkgbuilds/*` in dependency order and collects them in `pkgbuilds/out/`.
Runs as root; `makepkg` runs as `$BUILD_USER` (default `asphalt-build`, created
if needed). Packaged straight from the local checkouts, e.g. asphalt-firmware
from `../asphalt-firmware` (`ASPHALT_FIRMWARE_DIR` overrides).

```sh
cd <work>/linux-asphalt-build
sudo scripts/build-packages.sh --kernel <artifacts> linux-asphalt   # the modules of step 2
sudo scripts/build-packages.sh                          # everything except linux-asphalt
sudo scripts/build-packages.sh asphalt-device-support   # just one (or a few)
```

- Version numbers come from git (`r<count>.g<hash>`), so **commit first**:
  uncommitted changes build under the previous version number. A fresh clone is fine.
- `linux-asphalt` is built only with `--kernel <build-kernel.sh artifacts dir>`;
  it packages that build's modules (its version is the kernel release).
- See [pkgbuilds packages](../pkgbuilds/README.md) for what each package is.

## 4. Root filesystem: `build-rootfs.sh`

Builds a complete Arch Linux ARM root into a directory (or a mounted
partition), installs **every package in `pkgbuilds/out/`**, then the desktop
you choose. Run as root on ALARM (the chroot from step 1). It downloads the
ALARM tarball itself unless you pass `--tarball`.

```sh
sudo scripts/build-rootfs.sh --target /srv/rootfs \
    --user <name> --shell /usr/bin/fish --hostname asphalt --timezone Asia/Bangkok \
    --desktop hyprland --greeter /path/to/greeter-installer \
    --extra-packages my-packages.txt --ssh-key ~/.ssh/id_ed25519.pub
```

For a first build, `--target`, `--user` and `--desktop` are enough.

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

In the chroot (it has `mkfs.ext4`), write the image somewhere under `<work>`
so the host can see it:

```sh
du -sh /srv/rootfs        # the image needs this much, plus ~1 GiB of headroom
mkfs.ext4 -L asphalt-arch -U <ROOT_UUID> -E root_owner=0:0 -d /srv/rootfs <work>/asphalt-root.img 8G
```

- `<ROOT_UUID>` is the UUID the boot loader looks for:
  `grep -m1 '^ROOT_UUID=' <artifacts>/flash/init`. If it doesn't match, the tablet
  waits about 15 s, can't find root, and reboots.
- The label must match the root entry in the image's `/etc/fstab`
  (`LABEL=asphalt-arch`).
- `x-systemd.growfs` in fstab grows it to the whole partition on first boot,
  so the image only needs to fit the files.

### Where root lives

The loader checks `/dev/sda16` first, then every UFS partition
(`/dev/sd*`), microSD partition (`/dev/mmcblk*p*`) and NVMe partition, and boots the
first one whose filesystem UUID is `ROOT_UUID`. It scans **partitions**, not
whole disks, so the image has to go into a partition.

**microSD (recommended for a first try).** The card needs one partition at least
as big as the image. Everything on the card is erased.

- Linux host: partition the card, then
  `sudo dd if=asphalt-root.img of=/dev/sdX1 bs=4M conv=fsync status=progress`.
- macOS: find the card with `diskutil list` and **double-check the disk number**.
  `diskN` is a whole disk, and picking the wrong one wipes it. Then:
  ```sh
  diskutil partitionDisk diskN MBR FAT32 ASPHALT 100%   # one partition, sN = s1
  diskutil unmountDisk diskN
  sudo dd if=asphalt-root.img of=/dev/rdiskNs1 bs=4m
  ```
  The partition type says FAT. That doesn't matter, because Linux finds it by
  the ext4 UUID inside.

A card that works well in a Nintendo Switch (SanDisk Ultra / Extreme) is fine.
It's slower than UFS, but you don't have to repartition anything.

**UFS partition (advanced).** You need a free partition, for example by shrinking
`userdata`. Repartitioning wipes userdata, so back up first (see
[dual booting](../README.md#dual-booting)). The image is too big for one fastboot
download: write it from recovery
(`adb shell dd of=/dev/block/by-name/<partition>` with the image streamed in, e.g.
`adb exec-in`), or as a sparse image (`img2simg`).

## 6. Flashing (manual)

With the tablet in fastboot (from Android: `adb reboot bootloader`):

```sh
fastboot flash boot_b     <artifacts>/flash/boot.img
fastboot flash vendor_boot_b <artifacts>/flash/vendor_boot.img
fastboot --set-active=b && fastboot reboot
```

`<artifacts>/flash/FLASHING.txt` has the same commands with your paths filled in.

- **Always flash both images together.** The DTB lives in `vendor_boot`, so a
  `boot.img` on its own boots with the wrong device tree.
- **Don't flash `dtbo-retained.img`.** Slot B keeps the DTBO that's already on it.
- To go back: `fastboot --set-active=a && fastboot reboot` returns to Android.
  `flash/boot-recovery.img` + `vendor_boot-recovery.img` (the baseline pair)
  restore the previous Linux kernel.
- the script doesn't have automated image flashing, user **must** do it yourself,
  to avoid catastrophic error that will waste user time to restore with EDL package.

### Installing a new kernel (later builds)

The first image already contains the first kernel's modules (`linux-asphalt`).
For every later kernel, **its modules must be on the tablet before it boots**
(Wi-Fi is a module):

- Easiest: build `linux-asphalt` with `--kernel <artifacts>` and run
  `sudo pacman -U linux-asphalt-*.pkg.tar.*` on the tablet.
- By hand: `sudo tar --keep-directory-symlink -xzf modules.tar.gz -C /`, then
  `sudo depmod <release>`. **Never use plain `tar -xzf ... -C /`.** Arch has
  `/lib -> usr/lib`, and some tars replace that link with a directory, which
  breaks every program on the system. When copying from a Mac, use `rsync`, not macOS `tar`,
  which adds `._*` files.
- A DT-only change keeps the release, so only `vendor_boot.img` changes.

## Troubleshooting

| you see | it means / do this |
| --- | --- |
| `<out>/.config missing. First build?` | Add `--defconfig y700.config`. |
| `Baseline checksum mismatch` / `Baseline checksums must cover ...` | `SHA256SUMS` doesn't match the files. Re-download, or regenerate it ([step 0](#first-time-setup)). |
| `No such file or directory: .../kernel.release` | The baseline lacks `kernel.release`. See [step 0](#first-time-setup). |
| `Loader dependencies must be built-in: CONFIG_...` | Your config turned off something the loader needs before root is mounted. Set those to `=y`. |
| `Only Android boot header v4 is supported` / `Expected Android boot image` | The baseline isn't an asphalt boot pair (a stock image, or the files were swapped). |
| `Bootloader identity changed: ...` | Your DTB's `msm-id`, `board-id` or `region_country` differs from the baseline's. ABL picks the DTB by these, so it would reject it. |
| Errors about case, or files that exist twice, on macOS | The kernel tree isn't on a case-sensitive volume. |
| The tablet shows the logo, then reboots after ~25 s | The loader didn't find root: check the UUID (`blkid` from Linux / recovery) and that the card is seated. |
| The tablet goes straight back to fastboot or loops | Go back with `fastboot --set-active=a`, or flash the `*-recovery.img` pair to slot B. |
| It boots, but there's no Wi-Fi, sound or rotation | The modules for this kernel release are missing. See [installing a new kernel](#installing-a-new-kernel-later-builds). |

Still stuck? Open an [issue](https://github.com/lenovo-basements/linux-asphalt-build/issues)
with your `uname -r` (if it boots), `<artifacts>/package.log`,
`flash/manifest.json`, and the exact command and its output. Please read the
[AI policy](../README.md#issues-report-and-ai-policy) first.

## Other scripts

- `install-device-support.sh`: the pre-package way to copy `rootfs/` into a
  target (used by `build-rootfs.sh` only when no packages are in
  `pkgbuilds/out/`). Prefer the `asphalt-device-support` package.
- `get_pkgs.py`: downloads a few networking packages (iwd, wpa_supplicant,
  wireless-regdb, etc.) from the Arch mirrors for offline installs.
