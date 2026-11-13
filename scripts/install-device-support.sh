#!/bin/bash

set -euo pipefail

TARGET_ROOT=""
ENABLE_SERVICES=1

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --root <path>        Target rootfs directory (default: /)
  --no-enable-services Do not enable systemd services
  -h, --help           Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            TARGET_ROOT="$2"
            shift 2
            ;;
        --no-enable-services)
            ENABLE_SERVICES=0
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" == "Darwin" ]] && [[ -z "$TARGET_ROOT" || "$TARGET_ROOT" == "/" ]]; then
    echo "Error: You are running this script directly on macOS." >&2
    echo "To deploy directly to the tablet over SSH from macOS, use:" >&2
    echo "  scp -r rootfs/* root@192.168.77.2:/" >&2
    echo "Or to install to a mounted microSD rootfs on macOS, specify:" >&2
    echo "  sudo ./scripts/install-device-support.sh --root /Volumes/<disk>" >&2
    exit 1
fi

echo "=== Installing Legion Y700 (TB320FC) Device Support ==="
echo "Target root: ${TARGET_ROOT:-/}"

# Stock firmware, vendor configs and tools: sibling asphalt-firmware repo.
FIRMWARE_DIR="${FIRMWARE_DIR:-${REPO_DIR}/../asphalt-firmware}"

# 1. Install CLI utilities
echo "[1/5] Installing user binaries..."
mkdir -p "${TARGET_ROOT}/usr/local/bin"
install -m 755 "${REPO_DIR}/rootfs/usr/local/bin/"* "${TARGET_ROOT}/usr/local/bin/"
mkdir -p "${TARGET_ROOT}/usr/share/applications"
install -m 644 "${REPO_DIR}/rootfs/usr/share/applications/y700-chromium.desktop" "${TARGET_ROOT}/usr/share/applications/"
# Stock vendor sensor configs and the sensh tool live in the sibling
# asphalt-firmware repo, next to the stock firmware.
mkdir -p "${TARGET_ROOT}/usr/share/qcom/sensors"
cp -a "${FIRMWARE_DIR}/qcom/sensors/config" "${TARGET_ROOT}/usr/share/qcom/sensors/"
install -m 644 "${FIRMWARE_DIR}/qcom/sensors/sns_reg.conf" "${TARGET_ROOT}/usr/share/qcom/sensors/"
if [[ -f "${FIRMWARE_DIR}/tools/sensh" ]]; then
    install -m 755 "${FIRMWARE_DIR}/tools/sensh" "${TARGET_ROOT}/usr/local/bin/sensh"
else
    echo "Note: ${FIRMWARE_DIR}/tools/sensh not found; the lid sensor needs sensh." >&2
fi
mkdir -p "${TARGET_ROOT}/usr/lib/sysusers.d"
install -m 644 "${REPO_DIR}/rootfs/usr/lib/sysusers.d/y700-fastrpc.conf" "${TARGET_ROOT}/usr/lib/sysusers.d/"
if command -v systemd-sysusers >/dev/null 2>&1; then
    systemd-sysusers --root="${TARGET_ROOT:-/}" /usr/lib/sysusers.d/y700-fastrpc.conf
fi

# GNOME charging uses an authenticated helper, never world-writable sysfs.
mkdir -p "${TARGET_ROOT}/usr/share/polkit-1/actions"
install -m 644 "${REPO_DIR}/rootfs/usr/share/polkit-1/actions/local.lenovo.y700.charge.policy" \
    "${TARGET_ROOT}/usr/share/polkit-1/actions/"
mkdir -p "${TARGET_ROOT}/etc/polkit-1/rules.d"
install -m 644 "${REPO_DIR}/rootfs/etc/polkit-1/rules.d/49-y700-charge.rules" \
    "${TARGET_ROOT}/etc/polkit-1/rules.d/"
EXTENSION_DIR="usr/share/gnome-shell/extensions/y700-haptics@lenovo.local"
mkdir -p "${TARGET_ROOT}/${EXTENSION_DIR}"
install -m 644 "${REPO_DIR}/rootfs/${EXTENSION_DIR}/extension.js" \
    "${REPO_DIR}/rootfs/${EXTENSION_DIR}/metadata.json" "${TARGET_ROOT}/${EXTENSION_DIR}/"

# 2. Install udev rules
echo "[2/5] Installing udev rules..."
mkdir -p "${TARGET_ROOT}/etc/udev/rules.d"
install -m 644 "${REPO_DIR}/rootfs/etc/udev/rules.d/"*.rules "${TARGET_ROOT}/etc/udev/rules.d/"

# 3. Install feedbackd themes
echo "[3/5] Installing feedbackd themes..."
mkdir -p "${TARGET_ROOT}/etc/feedbackd/themes"
install -m 644 "${REPO_DIR}/rootfs/etc/feedbackd/themes/"*.json "${TARGET_ROOT}/etc/feedbackd/themes/"
# feedbackd only looks up device themes (named after the DT compatible) here.
mkdir -p "${TARGET_ROOT}/usr/local/share/feedbackd/themes"
install -m 644 "${REPO_DIR}/rootfs/usr/local/share/feedbackd/themes/"*.json "${TARGET_ROOT}/usr/local/share/feedbackd/themes/"

# 4. Install systemd units
echo "[4/5] Installing systemd services..."
mkdir -p "${TARGET_ROOT}/etc/systemd/system"
install -m 644 "${REPO_DIR}/rootfs/etc/systemd/system/"*.service "${TARGET_ROOT}/etc/systemd/system/"
install -m 644 "${REPO_DIR}/rootfs/etc/systemd/system/"*.socket "${TARGET_ROOT}/etc/systemd/system/"
mkdir -p "${TARGET_ROOT}/etc/systemd/logind.conf.d"
install -m 644 "${REPO_DIR}/rootfs/etc/systemd/logind.conf.d/"*.conf "${TARGET_ROOT}/etc/systemd/logind.conf.d/"
if [[ -d "${REPO_DIR}/rootfs/etc/systemd/system/getty@tty1.service.d" ]]; then
    mkdir -p "${TARGET_ROOT}/etc/systemd/system/getty@tty1.service.d"
    install -m 644 "${REPO_DIR}/rootfs/etc/systemd/system/getty@tty1.service.d/"*.conf "${TARGET_ROOT}/etc/systemd/system/getty@tty1.service.d/"
fi
if [[ -d "${REPO_DIR}/rootfs/etc/systemd/system/iio-sensor-proxy.service.d" ]]; then
    mkdir -p "${TARGET_ROOT}/etc/systemd/system/iio-sensor-proxy.service.d"
    install -m 644 "${REPO_DIR}/rootfs/etc/systemd/system/iio-sensor-proxy.service.d/"*.conf "${TARGET_ROOT}/etc/systemd/system/iio-sensor-proxy.service.d/"
fi
if [[ -d "${REPO_DIR}/rootfs/etc/systemd/user" ]]; then
    mkdir -p "${TARGET_ROOT}/etc/systemd/user"
    install -m 644 "${REPO_DIR}/rootfs/etc/systemd/user/"*.service "${TARGET_ROOT}/etc/systemd/user/"
fi
if [[ -d "${REPO_DIR}/rootfs/usr/lib/systemd/system-sleep" ]]; then
    mkdir -p "${TARGET_ROOT}/usr/lib/systemd/system-sleep"
    install -m 755 "${REPO_DIR}/rootfs/usr/lib/systemd/system-sleep/"* "${TARGET_ROOT}/usr/lib/systemd/system-sleep/"
fi

# 5. Install ALSA UCM2 audio profiles and WirePlumber configuration
echo "[5/5] Installing ALSA UCM2 and WirePlumber audio configs..."
UCM_BASE="${TARGET_ROOT}/usr/share/alsa/ucm2"
mkdir -p "${UCM_BASE}/Qualcomm/sm8450/Lenovo-TB320FC"
mkdir -p "${UCM_BASE}/conf.d/sm8450"

install -m 644 "${REPO_DIR}/rootfs/usr/share/alsa/ucm2/Qualcomm/sm8450/Lenovo-TB320FC/Lenovo-TB320FC.conf" \
               "${UCM_BASE}/Qualcomm/sm8450/Lenovo-TB320FC/"
install -m 644 "${REPO_DIR}/rootfs/usr/share/alsa/ucm2/Qualcomm/sm8450/Lenovo-TB320FC/HiFi.conf" \
               "${UCM_BASE}/Qualcomm/sm8450/Lenovo-TB320FC/"
install -m 644 "${REPO_DIR}/rootfs/usr/share/alsa/ucm2/conf.d/sm8450/Lenovo-TB320FC.conf" \
               "${UCM_BASE}/conf.d/sm8450/"

if [[ -d "${REPO_DIR}/rootfs/etc/wireplumber" ]]; then
    mkdir -p "${TARGET_ROOT}/etc/wireplumber/wireplumber.conf.d"
    install -m 644 "${REPO_DIR}/rootfs/etc/wireplumber/wireplumber.conf.d/"*.conf "${TARGET_ROOT}/etc/wireplumber/wireplumber.conf.d/"
fi

# libcamera soft-IPA tuning (CCMs from the vendor CamX tuning). libcamera searches
# /etc/libcamera/ipa before /usr/share/libcamera/ipa, so package files stay untouched.
mkdir -p "${TARGET_ROOT}/etc/libcamera/ipa/simple"
install -m 644 "${REPO_DIR}/rootfs/etc/libcamera/ipa/simple/"*.yaml "${TARGET_ROOT}/etc/libcamera/ipa/simple/"

# Stock signed VPU firmware (Iris), kept in the sibling asphalt-firmware repo.
# The explicit 2.4 name selects its firmware descriptor; the old name is kept
# for kernels predating that descriptor.
mkdir -p "${TARGET_ROOT}/lib/firmware/qcom/vpu"
install -m 644 "${FIRMWARE_DIR}/qcom/vpu/vpu20_p4.mbn" \
    "${TARGET_ROOT}/lib/firmware/qcom/vpu/vpu20_p4.mbn"
install -m 644 "${FIRMWARE_DIR}/qcom/vpu/vpu20_p4_gen2_v2_4.mbn" \
    "${TARGET_ROOT}/lib/firmware/qcom/vpu/vpu20_p4_gen2_v2_4.mbn"

# Power profiles (tuned-ppd keeps GNOME's power-mode menu working) and zram swap.
mkdir -p "${TARGET_ROOT}/etc/tuned/profiles"
cp -a "${REPO_DIR}/rootfs/etc/tuned/profiles/"y700-* "${TARGET_ROOT}/etc/tuned/profiles/"
install -m 644 "${REPO_DIR}/rootfs/etc/tuned/ppd.conf" "${TARGET_ROOT}/etc/tuned/ppd.conf"
install -m 644 "${REPO_DIR}/rootfs/etc/systemd/zram-generator.conf" "${TARGET_ROOT}/etc/systemd/zram-generator.conf"
mkdir -p "${TARGET_ROOT}/etc/sysctl.d"
install -m 644 "${REPO_DIR}/rootfs/etc/sysctl.d/"*.conf "${TARGET_ROOT}/etc/sysctl.d/"
mkdir -p "${TARGET_ROOT}/etc/tmpfiles.d"
install -m 644 "${REPO_DIR}/rootfs/etc/tmpfiles.d/"*.conf "${TARGET_ROOT}/etc/tmpfiles.d/"

# Enable systemd services if requested
if [[ "$ENABLE_SERVICES" -eq 1 ]]; then
    if [[ -z "$TARGET_ROOT" ]] || [[ "$TARGET_ROOT" == "/" ]]; then
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable pd-mapper.service 2>/dev/null || true
        systemctl enable hexagonrpcd-sdsp.service 2>/dev/null || true
        systemctl enable y700-touch-rightclick.service 2>/dev/null || true
        systemctl enable y700-lid-daemon.service 2>/dev/null || true
        systemctl enable y700-power-button.service 2>/dev/null || true
        systemctl enable y700-resume-guard.service
        systemctl enable y700-suspend-sensors.service
        systemctl enable y700-bluetooth-setup.service 2>/dev/null || true
        systemctl enable y700-wifi-mac.service 2>/dev/null || true
        systemctl enable y700-haptic-rtp.socket 2>/dev/null || true
        systemctl enable tuned.service tuned-ppd.service 2>/dev/null || true
        udevadm control --reload 2>/dev/null || true
        udevadm trigger 2>/dev/null || true
    else
        mkdir -p "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants"
        ln -sf ../pd-mapper.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/pd-mapper.service"
        ln -sf ../hexagonrpcd-sdsp.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/hexagonrpcd-sdsp.service"
        ln -sf ../y700-touch-rightclick.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/y700-touch-rightclick.service"
        ln -sf ../y700-lid-daemon.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/y700-lid-daemon.service"
        ln -sf ../y700-power-button.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/y700-power-button.service"
        mkdir -p "${TARGET_ROOT}/etc/systemd/system/sleep.target.wants"
        ln -sf ../y700-resume-guard.service "${TARGET_ROOT}/etc/systemd/system/sleep.target.wants/y700-resume-guard.service"
        mkdir -p "${TARGET_ROOT}/etc/systemd/system/sleep.target.requires"
        ln -sf ../y700-suspend-sensors.service "${TARGET_ROOT}/etc/systemd/system/sleep.target.requires/y700-suspend-sensors.service"
        ln -sf ../y700-bluetooth-setup.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/y700-bluetooth-setup.service"
        mkdir -p "${TARGET_ROOT}/etc/systemd/system/NetworkManager.service.wants"
        ln -sf ../y700-wifi-mac.service "${TARGET_ROOT}/etc/systemd/system/NetworkManager.service.wants/y700-wifi-mac.service"
        mkdir -p "${TARGET_ROOT}/etc/systemd/system/sockets.target.wants"
        ln -sf ../y700-haptic-rtp.socket "${TARGET_ROOT}/etc/systemd/system/sockets.target.wants/y700-haptic-rtp.socket"
        ln -sf /usr/lib/systemd/system/tuned.service "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/tuned.service"
        mkdir -p "${TARGET_ROOT}/etc/systemd/system/graphical.target.wants"
        ln -sf /usr/lib/systemd/system/tuned-ppd.service "${TARGET_ROOT}/etc/systemd/system/graphical.target.wants/tuned-ppd.service"
    fi
fi

echo "=== Legion Y700 device support installation complete! ==="
