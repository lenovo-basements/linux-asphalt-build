#!/bin/bash
# Build the TB320FC (Lenovo Legion Y700 Gen 2, "asphalt") kernel and package
#
#   scripts/kernel/build-kernel.sh --src ~/linux --baseline ~/asphalt-baseline \
#       --out /tmp/asphalt-build --artifacts ./out [--localversion -asphalt]
#
# Works on Linux (native arm64 or cross with LLVM) and on macOS (Homebrew
# llvm, lld, make, gnu-sed, coreutils). See scripts/kernel/README.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="" OUT="" ART="" BASELINE="" LOCALVERSION="" JOBS=""
DTB_NAME=sm8475-lenovo-tb320fc

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src) SRC="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --artifacts) ART="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        --localversion) LOCALVERSION="$2"; shift 2 ;;
        -j|--jobs) JOBS="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "unknown option: $1" >&2; usage 1 ;;
    esac
done
[[ -n "$SRC" && -n "$OUT" && -n "$ART" && -n "$BASELINE" ]] || usage 1
[[ -f "$OUT/.config" ]] || { echo "$OUT/.config missing: configure first (see README)" >&2; exit 1; }
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"
# Keep the builder's login and hostname out of the "Linux version" string.
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-asphalt}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-asphalt-build}"
mkdir -p "$ART/modules-root"
ART="$(cd "$ART" && pwd)"

make_args=(ARCH=arm64 LLVM=1)
if [[ "$(uname -s)" == Darwin ]]; then
    # macOS host: Homebrew toolchain plus small headers so the kernel's host
    # tools (modpost, gen_init_cpio, ...) build against Darwin's libc.
    brew="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
    export PATH="$brew/opt/gnu-sed/libexec/gnubin:$brew/opt/coreutils/libexec/gnubin:$brew/opt/llvm/bin:$brew/bin:$PATH"
    MAKE=gmake
    compat="$HERE/host-compat"
    make_args=(ARCH=arm64 "LLVM=$brew/opt/llvm/bin/" "LD=$brew/opt/lld/bin/ld.lld"
               HOSTCC=/usr/bin/clang HOSTCXX=/usr/bin/clang++
               "HOSTCFLAGS=-O2 -I $compat"
               "HOSTCFLAGS_file2alias.o=-include $compat/uuid.h"
               "HOSTCFLAGS_gen_init_cpio.o=-include $compat/gen-cpio.h"
               HOSTLDFLAGS=--ld-path=/usr/bin/ld)
else
    MAKE=make
fi
run_make() { "$MAKE" -C "$SRC" O="$OUT" "${make_args[@]}" "$@"; }

git -C "$SRC" rev-parse HEAD > "$ART/source.commit" 2>/dev/null || true
git -C "$SRC" diff HEAD --binary > "$ART/source.patch" 2>/dev/null || true
if [[ -n "$LOCALVERSION" ]]; then
    "$SRC/scripts/config" --file "$OUT/.config" --set-str LOCALVERSION "$LOCALVERSION"
fi
run_make olddefconfig
run_make -j"$JOBS" Image modules "qcom/$DTB_NAME.dtb"

cp "$OUT/arch/arm64/boot/Image" "$OUT/arch/arm64/boot/dts/qcom/$DTB_NAME.dtb" \
   "$OUT/include/config/kernel.release" "$ART/"
cp "$OUT/.config" "$ART/kernel.config"
DTC="$OUT/scripts/dtc/dtc" FDTOVERLAY="$OUT/scripts/dtc/fdtoverlay" \
    "$HERE/apply-abl.sh" "$ART/$DTB_NAME.dtb" "$ART/$DTB_NAME-abl.dtb"

rm -rf "$ART/modules-root"; mkdir -p "$ART/modules-root"
run_make DEPMOD=true INSTALL_MOD_PATH="$ART/modules-root" INSTALL_MOD_STRIP=1 modules_install
# Arch Linux ARM has /lib -> usr/lib, so ship the modules under usr/lib.
mv "$ART/modules-root/lib" "$ART/modules-root/usr-lib.tmp"
mkdir -p "$ART/modules-root/usr" && mv "$ART/modules-root/usr-lib.tmp" "$ART/modules-root/usr/lib"
tar_flags=(--owner=0 --group=0)
[[ "$(uname -s)" == Darwin ]] && tar_flags=(--uid 0 --gid 0 --uname root --gname root --no-xattrs)
(cd "$ART/modules-root" && COPYFILE_DISABLE=1 tar "${tar_flags[@]}" -czf ../modules.tar.gz usr)
echo "BUILD-OK $(cat "$ART/kernel.release")"

rm -rf "$ART/flash"
python3 "$HERE/package-boot.py" --baseline "$BASELINE" --image "$ART/Image" \
    --dtb "$ART/$DTB_NAME-abl.dtb" --config "$ART/kernel.config" \
    --kernel-release "$ART/kernel.release" --output "$ART/flash" > "$ART/package.log"
echo "PACKAGE-OK $ART/flash"
