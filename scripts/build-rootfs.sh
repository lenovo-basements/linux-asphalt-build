#!/bin/bash

set -euo pipefail

TARGET_ROOT=""
USERNAME="alarm"
PASSWORD=""
HOSTNAME="y700"
TARBALL_PATH=""
ENABLE_GNOME=1
ENABLE_AUTOLOGIN=1
FIRMWARE_SRC=""

usage() {
    cat <<EOF
Usage: $0 --target <directory> [options]

Options:
  --target <path>        Target rootfs mount directory (Required)
  --user <username>      Primary user to create (default: alarm, as on Arch Linux ARM)
  --password <password>  Password for that user (default: same as the username)
  --hostname <name>      System hostname (default: y700)
  --tarball <path>       Path to existing ArchLinuxARM-aarch64-latest.tar.gz
  --firmware-dir <path>  Path to asphalt-firmware repository
  --no-gnome             Do not install GNOME desktop environment
  --no-autologin         Do not enable automatic login in GDM
  -h, --help             Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_ROOT="$2"
            shift 2
            ;;
        --user)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --tarball)
            TARBALL_PATH="$2"
            shift 2
            ;;
        --firmware-dir)
            FIRMWARE_SRC="$2"
            shift 2
            ;;
        --no-gnome)
            ENABLE_GNOME=0
            shift
            ;;
        --no-autologin)
            ENABLE_AUTOLOGIN=0
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

if [[ -z "$TARGET_ROOT" ]]; then
    echo "Error: --target directory is required." >&2
    usage
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: This script must be run as root (or with sudo)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Discover firmware directory if not specified
if [[ -z "$FIRMWARE_SRC" ]]; then
    if [[ -d "${REPO_DIR}/../asphalt-firmware" ]]; then
        FIRMWARE_SRC="$(cd "${REPO_DIR}/../asphalt-firmware" && pwd)"
    elif [[ -d "/lib/firmware/qcom/lenovo/tb320fc" ]]; then
        FIRMWARE_SRC="/lib/firmware"
    fi
fi

mkdir -p "$TARGET_ROOT"

echo "=== [1/8] Installing packages into target rootfs ==="

CORE_PKGS=(
    base base-devel sudo networkmanager i2c-tools
    zsh bash fish nano vim git htop wget curl
    parted e2fsprogs f2fs-tools dosfstools exfatprogs
    linux-firmware wireless-regdb iw
    bluez bluez-utils
    mesa vulkan-freedreno
    pipewire pipewire-pulse pipewire-alsa pipewire-libcamera wireplumber rtkit alsa-utils alsa-ucm-conf libcamera v4l-utils
    iio-sensor-proxy upower tuned tuned-ppd zram-generator brightnessctl noto-fonts-cjk
    otf-ipafont otf-ipaexfont
)

GNOME_PKGS=()
if [[ "$ENABLE_GNOME" -eq 1 ]]; then
    GNOME_PKGS=(
        gnome-shell gdm nautilus gnome-control-center
        gnome-terminal gnome-keyring gnome-tweaks gnome-backgrounds snapshot
        xdg-user-dirs dconf polkit
    )
fi

ALL_PKGS=("${CORE_PKGS[@]}" "${GNOME_PKGS[@]}")

if command -v pacstrap >/dev/null 2>&1; then
    echo "Using pacstrap with package cache..."
    pacstrap -K -c "$TARGET_ROOT" "${ALL_PKGS[@]}"
else
    TARBALL_URL="http://mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
    CACHE_DIR="/var/cache/asphalt-build"
    mkdir -p "$CACHE_DIR"

    if [[ -z "$TARBALL_PATH" || ! -f "$TARBALL_PATH" ]]; then
        TARBALL_PATH="${CACHE_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"
        if [[ ! -f "$TARBALL_PATH" ]]; then
            echo "Downloading Arch Linux ARM aarch64 base tarball..."
            curl -L -C - -o "$TARBALL_PATH" "$TARBALL_URL" || wget -c -O "$TARBALL_PATH" "$TARBALL_URL"
        else
            echo "Using cached tarball: $TARBALL_PATH"
        fi
    fi

    echo "Extracting base system to $TARGET_ROOT..."
    bsdtar -xpf "$TARBALL_PATH" -C "$TARGET_ROOT"

    echo "Initializing pacman keys..."
    cp /etc/resolv.conf "${TARGET_ROOT}/etc/resolv.conf"
    chroot "$TARGET_ROOT" pacman-key --init
    chroot "$TARGET_ROOT" pacman-key --populate archlinuxarm
    chroot "$TARGET_ROOT" pacman -Syu --noconfirm --needed "${ALL_PKGS[@]}"
fi

LOCAL_PKGS=()
shopt -s nullglob
for pkg in "${REPO_DIR}/pkgbuilds/out/"*.pkg.tar.*; do
    [[ $pkg == *.sig ]] || LOCAL_PKGS+=("$pkg")
done
shopt -u nullglob
if [[ ${#LOCAL_PKGS[@]} -gt 0 ]]; then
    echo "Installing ${#LOCAL_PKGS[@]} local package(s) from pkgbuilds/out/..."
    mkdir -p "${TARGET_ROOT}/var/cache/asphalt-pkgs"
    cp "${LOCAL_PKGS[@]}" "${TARGET_ROOT}/var/cache/asphalt-pkgs/"
    chroot "$TARGET_ROOT" sh -c 'pacman -U --noconfirm /var/cache/asphalt-pkgs/*.pkg.tar.*'
    rm -rf "${TARGET_ROOT}/var/cache/asphalt-pkgs"
fi

# Account tools must retain their package setuid bits when extracting/copying
# the rootfs. Without them chsh fails with setpwnam and passwd also breaks.
for tool in chsh passwd; do
    if ! chroot "$TARGET_ROOT" test -u "/usr/bin/$tool"; then
        echo "Error: /usr/bin/$tool lost its package setuid permission in the target rootfs." >&2
        echo "Check extraction/copy ownership and reinstall util-linux/shadow in the target." >&2
        exit 1
    fi
done

echo "=== [2/8] Configuring networking and hostname ==="
cp /etc/resolv.conf "${TARGET_ROOT}/etc/resolv.conf" 2>/dev/null || true
echo "$HOSTNAME" > "${TARGET_ROOT}/etc/hostname"

cat <<EOF > "${TARGET_ROOT}/etc/hosts"
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "=== [4/8] Configuring user '$USERNAME' ==="
USER_GROUPS="wheel,video,audio,input,render,storage,network"
if chroot "$TARGET_ROOT" id -u "$USERNAME" >/dev/null 2>&1; then
    # e.g. the stock "alarm" user from the Arch Linux ARM tarball
    chroot "$TARGET_ROOT" usermod -a -G "$USER_GROUPS" "$USERNAME"
else
    chroot "$TARGET_ROOT" useradd -m -g users -G "$USER_GROUPS" -s /bin/bash "$USERNAME"
fi

mkdir -p "${TARGET_ROOT}/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "${TARGET_ROOT}/etc/sudoers.d/00-wheel-nopasswd"
chmod 440 "${TARGET_ROOT}/etc/sudoers.d/00-wheel-nopasswd"

# Default password is the username (Arch Linux ARM convention); change it.
echo "${USERNAME}:${PASSWORD:-$USERNAME}" | chroot "$TARGET_ROOT" chpasswd
echo "root:root" | chroot "$TARGET_ROOT" chpasswd

# microSD cards mount at /mnt/microsd (89-y700-microsd.rules); FAT/exFAT
# files belong to the primary user.
printf 'MICROSD_USER=%s\n' "$USERNAME" > "${TARGET_ROOT}/etc/y700-microsd.conf"

echo "=== [5/8] Configuring GDM, Auto-Login & On-Screen Keyboard ==="
if [[ "$ENABLE_GNOME" -eq 1 ]]; then
    # Enable graphical target and GDM
    systemctl --root="$TARGET_ROOT" set-default graphical.target
    systemctl --root="$TARGET_ROOT" enable gdm.service

    # Enable NetworkManager and Bluetooth
    systemctl --root="$TARGET_ROOT" enable NetworkManager.service
    systemctl --root="$TARGET_ROOT" enable bluetooth.service

    # GDM Auto-login
    if [[ "$ENABLE_AUTOLOGIN" -eq 1 ]]; then
        echo "Configuring automatic login for '$USERNAME'..."
        mkdir -p "${TARGET_ROOT}/etc/gdm"
        cat <<EOF > "${TARGET_ROOT}/etc/gdm/custom.conf"
# GDM configuration for Lenovo Legion Y700 (TB320FC)
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=${USERNAME}
WaylandEnable=true

[security]

[debug]
EOF
    fi

    # On-Screen Keyboard configuration via dconf
    echo "Configuring On-Screen Keyboard default enabled..."
    mkdir -p "${TARGET_ROOT}/etc/dconf/db/gdm.d"
    mkdir -p "${TARGET_ROOT}/etc/dconf/db/local.d"
    mkdir -p "${TARGET_ROOT}/etc/dconf/profile"

    cat <<EOF > "${TARGET_ROOT}/etc/dconf/profile/gdm"
user-db:user
system-db:gdm
EOF

    cat <<EOF > "${TARGET_ROOT}/etc/dconf/profile/user"
user-db:user
system-db:local
EOF

    cat <<EOF > "${TARGET_ROOT}/etc/dconf/db/gdm.d/06-osk"
[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=true
EOF

    cat <<EOF > "${TARGET_ROOT}/etc/dconf/db/local.d/06-osk"
[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=true

[org/gnome/shell]
enabled-extensions=['y700-haptics@lenovo.local']

[org/gnome/mutter]
auto-maximize=true
center-new-windows=true
EOF

    chroot "$TARGET_ROOT" dconf update || true
fi

echo "=== [6/8] Installing Legion Y700 device support ==="
if [[ -f "${SCRIPT_DIR}/install-device-support.sh" ]]; then
    bash "${SCRIPT_DIR}/install-device-support.sh" --root "$TARGET_ROOT"
fi

echo "=== [7/8] Installing device firmware ==="
if [[ -n "$FIRMWARE_SRC" && -d "$FIRMWARE_SRC" ]]; then
    echo "Installing device-specific firmware from $FIRMWARE_SRC..."
    mkdir -p "${TARGET_ROOT}/lib/firmware"
    
    # Copy TB320FC firmware components
    for comp in ath11k cirrus novatek qca qcom awinic; do
        if [[ -d "${FIRMWARE_SRC}/${comp}" ]]; then
            mkdir -p "${TARGET_ROOT}/lib/firmware/${comp}"
            cp -r "${FIRMWARE_SRC}/${comp}/"* "${TARGET_ROOT}/lib/firmware/${comp}/" 2>/dev/null || true
        fi
    done
fi

echo "=== [8/8] Installing kernel modules ==="
if [[ -d "/lib/modules" ]]; then
    CURRENT_KVER="$(uname -r)"
    if [[ -d "/lib/modules/${CURRENT_KVER}" ]]; then
        echo "Copying running kernel modules (${CURRENT_KVER})..."
        mkdir -p "${TARGET_ROOT}/lib/modules/${CURRENT_KVER}"
        cp -a "/lib/modules/${CURRENT_KVER}" "${TARGET_ROOT}/lib/modules/"
    fi
fi

# Basic fstab template
cat <<EOF > "${TARGET_ROOT}/etc/fstab"
# /etc/fstab: static file system information
# <file system>             <mount point>  <type>  <options>       <dump>  <pass>
LABEL=y700-arch             /              ext4    rw,noatime      0       1
# Factory sensor calibration is copied into /var/lib on first sensor startup.
/dev/disk/by-partlabel/persist /mnt/persist  ext4    ro,nofail       0       0
EOF
MICROSD_UID=$(chroot "$TARGET_ROOT" id -u "$USERNAME")
MICROSD_GID=$(chroot "$TARGET_ROOT" id -g "$USERNAME")
# File-manager re-mounts (udisks) follow this line to the microSD service's
# path; the symlink comes from 89-y700-microsd.rules (FAT-family cards only,
# the line carries uid/gid).
printf '/dev/disk/y700-microsd      /mnt/microsd   auto    noauto,nofail,noatime,nosuid,nodev,exec,uid=%s,gid=%s,umask=022,x-gvfs-show 0 0\n' \
    "$MICROSD_UID" "$MICROSD_GID" >> "${TARGET_ROOT}/etc/fstab"

echo ""
echo "==========================================================="
echo "=== Arch Linux ARM Rootfs Generation Complete! ==="
echo "Target directory: $TARGET_ROOT"
if [[ -n "$PASSWORD" ]]; then
    echo "Primary user:     $USERNAME (password set with --password)"
else
    echo "Primary user:     $USERNAME (password: $USERNAME)"
fi
echo "WARNING: root's password is 'root' and wheel has passwordless sudo."
echo "         Change both passwords (passwd; sudo passwd root) before using a network."
echo "Autologin:        $([ $ENABLE_AUTOLOGIN -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo "GNOME Desktop:    $([ $ENABLE_GNOME -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo "==========================================================="
