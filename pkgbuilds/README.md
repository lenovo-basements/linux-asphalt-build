# Device packages

Rebuilds of Arch Linux ARM packages that need device patches. Build them **on the tablet**
(aarch64) and drop the results in `out/`; `scripts/build-rootfs.sh` installs every
`out/*.pkg.tar.*` into the image with `pacman -U` after the stock packages.

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
