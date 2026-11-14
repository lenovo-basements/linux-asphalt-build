#!/bin/bash
# Build the asphalt packages (pkgbuilds/*) on an aarch64 Arch Linux ARM system
# -- the tablet itself, or a clean ALARM chroot -- in dependency order, and
# collect them in pkgbuilds/out/. Runs as root; makepkg runs as $BUILD_USER.
#
#   sudo scripts/build-packages.sh [--kernel <build-kernel.sh output dir>] [pkg ...]
#
# Without package names it builds all of them. linux-asphalt is only built
# with --kernel. Built packages that others need at build time (qrtr) are
# installed into this system as they come out.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRMWARE_DIR="${ASPHALT_FIRMWARE_DIR:-$REPO_DIR/../asphalt-firmware}"
PEN_DIR="${ASPHALT_PEN_DIR:-$REPO_DIR/../asphalt-pen-service}"
BUILD_USER="${BUILD_USER:-asphalt-build}"
WORK="${WORK:-/var/tmp/asphalt-pkgbuild}"
OUT="$REPO_DIR/pkgbuilds/out"
KERNEL_BUILD=""

ORDER=(qrtr pd-mapper hexagonrpc sensh qcom-va-driver hyprgrass libcamera
       asphalt-firmware asphalt-pen-service asphalt-device-support linux-asphalt)
# Packaged straight from local checkouts; nothing to resolve at build time.
NODEPS=(asphalt-firmware asphalt-pen-service asphalt-device-support linux-asphalt)
# Needed by later builds: install as soon as they're built.
INSTALL_AFTER=(qrtr)

pkgs=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel) KERNEL_BUILD="$(cd "$2" && pwd)"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) pkgs+=("$1"); shift ;;
    esac
done
if [[ ${#pkgs[@]} -eq 0 ]]; then
    pkgs=("${ORDER[@]}")
    [[ -n $KERNEL_BUILD ]] || pkgs=("${pkgs[@]/linux-asphalt}")
fi
[[ $(id -u) -eq 0 ]] || { echo "Run as root (makepkg itself runs as $BUILD_USER)." >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo "Build on aarch64 Arch Linux ARM." >&2; exit 1; }

id "$BUILD_USER" >/dev/null 2>&1 || useradd -r -m -d "/var/lib/$BUILD_USER" "$BUILD_USER"
echo "$BUILD_USER ALL=(root) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/90-asphalt-build
chmod 440 /etc/sudoers.d/90-asphalt-build
# The checkouts are usually owned by someone else (or a host mount).
sudo -u "$BUILD_USER" git config --global --replace-all safe.directory '*'
pacman -S --needed --noconfirm base-devel git >/dev/null

in_list() { local x="$1"; shift; for y; do [[ $x == "$y" ]] && return 0; done; return 1; }

mkdir -p "$OUT"
for pkg in "${ORDER[@]}"; do
    in_list "$pkg" "${pkgs[@]}" || continue
    echo "=== $pkg ==="
    rm -rf "$WORK/$pkg"
    mkdir -p "$WORK"
    cp -rL "$REPO_DIR/pkgbuilds/$pkg" "$WORK/$pkg"
    rm -f "$WORK/$pkg"/*.pkg.tar.*
    chown -R "$BUILD_USER:" "$WORK/$pkg"
    flags=(--syncdeps --noconfirm --clean --cleanbuild --force)
    in_list "$pkg" "${NODEPS[@]}" && flags+=(--nodeps)
    (cd "$WORK/$pkg" && sudo -u "$BUILD_USER" \
        ASPHALT_BUILD_DIR="$REPO_DIR" ASPHALT_FIRMWARE_DIR="$FIRMWARE_DIR" \
        ASPHALT_PEN_DIR="$PEN_DIR" ASPHALT_KERNEL_BUILD="$KERNEL_BUILD" \
        PKGDEST="$WORK/$pkg" makepkg "${flags[@]}")
    built=("$WORK/$pkg"/*.pkg.tar.*)
    in_list "$pkg" "${INSTALL_AFTER[@]}" && pacman -U --noconfirm "${built[@]}"
    # Drop older builds of the same packages, keep the new ones.
    for f in "${built[@]}"; do
        name=$(pacman -Qqp "$f")
        for old in "$OUT"/*.pkg.tar.*; do
            [[ -e $old ]] && [[ $(pacman -Qqp "$old" 2>/dev/null) == "$name" ]] && rm -f "$old"
        done
    done
    cp "${built[@]}" "$OUT/"
done
ls -la "$OUT"
