# Device packages

Everything the TB320FC needs beyond stock Arch Linux ARM, as pacman packages: nothing is
hand-copied into `/usr/local` or `/etc`. `scripts/build-rootfs.sh` installs every
`out/*.pkg.tar.*` into the image with `pacman -U` after the stock packages; on a running
system `pacman -U out/*.pkg.tar.*` updates them.

| package | what | source |
|---|---|---|
| `asphalt-device-support` | daemons, units, udev, UCM, WirePlumber, tuned, haptics, sensors glue (`../rootfs`) | this repo |
| `asphalt-firmware` | device firmware + SSC sensor configs | `../../asphalt-firmware` |
| `linux-asphalt` | modules (+ Image, DTBs, boot images for reference) of one kernel build | a `build-kernel.sh` output dir |
| `asphalt-pen-service` | pen mode while a BT pen is connected | `../../asphalt-pen-service` |
| `qrtr`, `pd-mapper` | QRTR library/tools, protection-domain mapper | upstream, pinned |
| `hexagonrpc` | FastRPC server for the sensor DSP (+ local changes) | upstream + patch |
| `sensh` | SSC sensor shell + `sscregistrygen` (+ local changes) | upstream + patches |
| `qcom-va-driver` | VA-API on Iris (Brave, mpv) | radxa-pkg, pinned |
| `hyprgrass` | Hyprland touch gestures, pinned for the dotfiles | upstream + wf-touch submodule |
| `libcamera` | Arch's libcamera + sensor helpers (below) | Arch PKGBUILD + patches |

Build them all on aarch64 Arch Linux ARM (the tablet, or a clean ALARM chroot) as root:

```
sudo scripts/build-packages.sh --kernel ../bringup-artifacts/<build>   # all, in dependency order
sudo scripts/build-packages.sh sensh hexagonrpc                         # just these
```

Notes:
- **Services aren't enabled on install** (Arch convention). The image enables the set in
  `/usr/lib/systemd/system-preset/80-asphalt.preset`; on an existing system run the
  `systemctl preset ...` line the package prints.
- **tuned-ppd** only reads `/etc/tuned/ppd.conf`, which belongs to `tuned-ppd`: the y700
  mapping ships as `/usr/share/asphalt/tuned-ppd.conf`; build-rootfs copies it over.
- **hyprgrass depends on the exact `hyprland` version it was built with**, so pacman refuses
  a Hyprland update until hyprgrass is rebuilt (`build-packages.sh hyprgrass`, then update
  both together). Its `/usr/lib/hyprgrass/libhyprgrass.json` is the metadata
  `gesture-control` checks.
- **linux-asphalt doesn't flash anything.** ABL boots the boot/vendor_boot partitions, so a
  new kernel still means flashing that build's `flash/*.img`; the package keeps the modules
  in step with it.

## libcamera

Arch's `libcamera` 0.7.2-4 split package plus the sensor helpers / sensor properties for
ov13b10, s5k4h7 and sc202cs (`../patches/libcamera`, symlinked here). Docs, qcam, tests,
python and gstreamer are left out to keep makedepends small; the package names match Arch's,
so `pipewire-libcamera` and friends stay happy.

```
cd pkgbuilds/libcamera
makepkg -sf            # ~3 min on the tablet
sudo pacman -U libcamera-*.pkg.tar.* libcamera-ipa-*.pkg.tar.* libcamera-tools-*.pkg.tar.*
cp *.pkg.tar.* ../out/
```

Notes:
- `pkgrel=4.1` sorts above Arch's `4`; an Arch rebuild to `-5` replaces it, so rebuild (or add
  the three names to `IgnorePkg`) after such an update.
- `-D werror=false`: GCC 16 trips `-Warray-bounds` inside libstdc++'s std::mutex.
- `-D rpi-awb-nn=disabled`: `arch-meson` enables every auto feature; this one needs tensorflow-lite.
- Colour tuning (CCMs) is separate: `rootfs/etc/libcamera/ipa/simple/*.yaml`, picked up by
  stock and patched libcamera alike.
