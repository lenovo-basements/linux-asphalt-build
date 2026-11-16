#!/bin/bash

set -euo pipefail

TARGET_ROOT=""
USERNAME="alarm"
PASSWORD=""
HOSTNAME="asphalt"
TIMEZONE="UTC"
TARBALL_PATH=""
DESKTOP="none"
ENABLE_AUTOLOGIN=1
FIRMWARE_SRC=""
GREETER_INSTALL=""
EXTRA_PACKAGES=""
USER_SHELL="/bin/bash"
SSH_KEY=""

usage() {
    cat <<EOF
Usage: $0 --target <directory> [options]

Options:
  --target <path>        Target rootfs mount directory (Required)
  --user <username>      Primary user to create (default: alarm, as on Arch Linux ARM)
  --password <password>  Password for that user (default: same as the username)
  --hostname <name>      System hostname (default: asphalt)
  --timezone <zone>      tz database zone, e.g. Asia/Bangkok (default: UTC)
  --tarball <path>       Path to existing ArchLinuxARM-aarch64-latest.tar.gz
  --firmware-dir <path>  Path to asphalt-firmware repository
  --desktop <name>       none (default: console login on tty1, no desktop),
                         gnome, or hyprland
  --no-gnome             Same as --desktop none (kept for old scripts)
  --no-autologin         Desktops only: no automatic login (GDM, or greetd
                         for hyprland). The console always asks for a login.
  --greeter <script>     hyprland: run this greeter installer (e.g. the
                         dotfiles' greeter/install-greeter) instead of autologin
  --extra-packages <file>  Also install the packages listed in <file>
                         (whitespace-separated, # comments)
  --shell <path>         Login shell for the user (default: /bin/bash)
  --ssh-key <file>       Enable sshd, key-only, with this authorized_keys file
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
        --timezone)
            TIMEZONE="$2"
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
        --desktop)
            DESKTOP="$2"
            shift 2
            ;;
        --no-gnome)
            DESKTOP="none"
            shift
            ;;
        --greeter)
            GREETER_INSTALL="$2"
            shift 2
            ;;
        --extra-packages)
            EXTRA_PACKAGES="$2"
            shift 2
            ;;
        --shell)
            USER_SHELL="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
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

case "$DESKTOP" in
    gnome|hyprland|none) ;;
    *) echo "Error: --desktop must be gnome, hyprland or none." >&2; exit 1 ;;
esac
if [[ -n "$GREETER_INSTALL" && "$DESKTOP" != hyprland ]]; then
    echo "Error: --greeter needs --desktop hyprland." >&2
    exit 1
fi
ENABLE_GNOME=0
[[ "$DESKTOP" == gnome ]] && ENABLE_GNOME=1
for f in "$GREETER_INSTALL" "$EXTRA_PACKAGES" "$SSH_KEY"; do
    if [[ -n "$f" && ! -f "$f" ]]; then
        echo "Error: $f not found." >&2
        exit 1
    fi
done

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
    elif [[ -d "/lib/firmware/qcom/lenovo/asphalt" ]]; then
        FIRMWARE_SRC="/lib/firmware"
    fi
fi

mkdir -p "$TARGET_ROOT"

# arch-chroot mounts /proc, /dev, ... for package hooks; plain chroot is the
# fallback. pacman also wants the target to be a mount point (free-space
# check), so a plain directory gets bind-mounted onto itself for the build.
CHROOT=(chroot)
command -v arch-chroot >/dev/null 2>&1 && CHROOT=(arch-chroot)
if command -v mountpoint >/dev/null 2>&1 && ! mountpoint -q "$TARGET_ROOT"; then
    mount --bind "$TARGET_ROOT" "$TARGET_ROOT"
    trap 'umount "$TARGET_ROOT" 2>/dev/null || true' EXIT
fi

echo "=== [1/8] Installing packages into target rootfs ==="

CORE_PKGS=(
    base base-devel archlinuxarm-keyring sudo networkmanager i2c-tools
    zsh bash fish nano vim git htop wget curl
    parted e2fsprogs f2fs-tools dosfstools exfatprogs
    wireless-regdb iw openssh
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

# Hyprland desktop: greetd, Quickshell, and the touch pieces (on-screen
# keyboard + its haptics, polkit agent, portals).
HYPR_PKGS=()
if [[ "$DESKTOP" == hyprland ]]; then
    HYPR_PKGS=(
        hyprland xdg-desktop-portal-hyprland hyprpolkitagent hypridle
        greetd quickshell mako fuzzel kitty squeekboard feedbackd
        wl-clipboard grim nautilus gnome-keyring xdg-user-dirs dconf polkit
    )
fi

EXTRA_PKGS=()
if [[ -n "$EXTRA_PACKAGES" ]]; then
    mapfile -t EXTRA_PKGS < <(sed 's/#.*//' "$EXTRA_PACKAGES" | tr -s '[:space:]' '\n' | sed '/^$/d')
fi

ALL_PKGS=("${CORE_PKGS[@]}" "${GNOME_PKGS[@]}" "${HYPR_PKGS[@]}" "${EXTRA_PKGS[@]}")

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
    "${CHROOT[@]}" "$TARGET_ROOT" pacman-key --init
    "${CHROOT[@]}" "$TARGET_ROOT" pacman-key --populate archlinuxarm
    "${CHROOT[@]}" "$TARGET_ROOT" pacman -Syu --noconfirm --needed "${ALL_PKGS[@]}"
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
    "${CHROOT[@]}" "$TARGET_ROOT" sh -c 'pacman -U --noconfirm /var/cache/asphalt-pkgs/*.pkg.tar.*'
    rm -rf "${TARGET_ROOT}/var/cache/asphalt-pkgs"
fi

# Account tools must retain their package setuid bits when extracting/copying
# the rootfs. Without them chsh fails with setpwnam and passwd also breaks.
for tool in chsh passwd; do
    if ! "${CHROOT[@]}" "$TARGET_ROOT" test -u "/usr/bin/$tool"; then
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
if "${CHROOT[@]}" "$TARGET_ROOT" id -u "$USERNAME" >/dev/null 2>&1; then
    # e.g. the stock "alarm" user from the Arch Linux ARM tarball
    "${CHROOT[@]}" "$TARGET_ROOT" usermod -a -G "$USER_GROUPS" "$USERNAME"
else
    "${CHROOT[@]}" "$TARGET_ROOT" useradd -m -g users -G "$USER_GROUPS" -s "$USER_SHELL" "$USERNAME"
fi
"${CHROOT[@]}" "$TARGET_ROOT" chsh -s "$USER_SHELL" "$USERNAME" >/dev/null

mkdir -p "${TARGET_ROOT}/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "${TARGET_ROOT}/etc/sudoers.d/00-wheel-nopasswd"
chmod 440 "${TARGET_ROOT}/etc/sudoers.d/00-wheel-nopasswd"

# Default password is the username (Arch Linux ARM convention); change it.
echo "${USERNAME}:${PASSWORD:-$USERNAME}" | "${CHROOT[@]}" "$TARGET_ROOT" chpasswd
echo "root:root" | "${CHROOT[@]}" "$TARGET_ROOT" chpasswd

# microSD cards mount at /mnt/microsd (89-asphalt-microsd.rules); FAT/exFAT
# files belong to the primary user.
printf 'MICROSD_USER=%s\n' "$USERNAME" > "${TARGET_ROOT}/etc/asphalt-microsd.conf"

echo "=== [5/8] Configuring services, desktop & login ==="

# Every image needs these, whatever the desktop. The PMIC RTC can't be set
# from Linux (it reads 1970), so without NTP the clock only has systemd's
# saved timestamp from the last shutdown.
systemctl --root="$TARGET_ROOT" enable NetworkManager.service bluetooth.service \
    systemd-timesyncd.service
if [[ ! -e "${TARGET_ROOT}/usr/share/zoneinfo/${TIMEZONE}" ]]; then
    echo "Unknown timezone: ${TIMEZONE}" >&2
    exit 1
fi
ln -sfn "/usr/share/zoneinfo/${TIMEZONE}" "${TARGET_ROOT}/etc/localtime"

if [[ "$DESKTOP" == none ]]; then
    # Console only: boot to a getty login prompt, nothing graphical waits.
    systemctl --root="$TARGET_ROOT" set-default multi-user.target
fi

if [[ -n "$SSH_KEY" ]]; then
    echo "Enabling sshd (key-only) for '$USERNAME'..."
    USER_HOME=$("${CHROOT[@]}" "$TARGET_ROOT" getent passwd "$USERNAME" | cut -d: -f6)
    install -d -m700 "${TARGET_ROOT}${USER_HOME}/.ssh"
    install -m600 "$SSH_KEY" "${TARGET_ROOT}${USER_HOME}/.ssh/authorized_keys"
    "${CHROOT[@]}" "$TARGET_ROOT" chown -R "$USERNAME:" "${USER_HOME}/.ssh"
    mkdir -p "${TARGET_ROOT}/etc/ssh/sshd_config.d"
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' \
        > "${TARGET_ROOT}/etc/ssh/sshd_config.d/10-asphalt-keys-only.conf"
    systemctl --root="$TARGET_ROOT" enable sshd.service
fi

if [[ "$DESKTOP" == hyprland ]]; then
    systemctl --root="$TARGET_ROOT" set-default graphical.target
    systemctl --root="$TARGET_ROOT" enable greetd.service
    if [[ -n "$GREETER_INSTALL" ]]; then
        bash "$GREETER_INSTALL" --root "$TARGET_ROOT" --user "$USERNAME"
    else
        # No touch greeter: agreety on the console (needs a keyboard), plus
        # autologin straight into Hyprland unless --no-autologin.
        mkdir -p "${TARGET_ROOT}/etc/greetd"
        {
            printf '[terminal]\nvt = 1\n\n[default_session]\n'
            printf 'command = "agreety --cmd start-hyprland"\nuser = "greeter"\n'
            if [[ "$ENABLE_AUTOLOGIN" -eq 1 ]]; then
                printf '\n[initial_session]\ncommand = "start-hyprland"\nuser = "%s"\n' "$USERNAME"
            fi
        } > "${TARGET_ROOT}/etc/greetd/config.toml"
    fi
fi

if [[ "$ENABLE_GNOME" -eq 1 ]]; then
    # Enable graphical target and GDM
    systemctl --root="$TARGET_ROOT" set-default graphical.target
    systemctl --root="$TARGET_ROOT" enable gdm.service

    # GDM Auto-login
    if [[ "$ENABLE_AUTOLOGIN" -eq 1 ]]; then
        echo "Configuring automatic login for '$USERNAME'..."
        mkdir -p "${TARGET_ROOT}/etc/gdm"
        cat <<EOF > "${TARGET_ROOT}/etc/gdm/custom.conf"
# GDM configuration for Lenovo Legion Y700 Gen 2 (asphalt)
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
enabled-extensions=['asphalt-haptics@lenovo.local']

[org/gnome/mutter]
auto-maximize=true
center-new-windows=true
EOF

    "${CHROOT[@]}" "$TARGET_ROOT" dconf update || true
fi

has_pkg() { "${CHROOT[@]}" "$TARGET_ROOT" pacman -Q "$1" >/dev/null 2>&1; }

echo "=== [6/8] Installing Legion Y700 device support ==="
if has_pkg asphalt-device-support; then
    # Packaged (pkgbuilds/asphalt-device-support): enable its preset set.
    mapfile -t PRESET_UNITS < <(sed -n 's/^enable //p' \
        "${TARGET_ROOT}/usr/lib/systemd/system-preset/80-asphalt.preset")
    systemctl --root="$TARGET_ROOT" preset "${PRESET_UNITS[@]}"
    install -m644 "${TARGET_ROOT}/usr/share/asphalt/tuned-ppd.conf" "${TARGET_ROOT}/etc/tuned/ppd.conf"
elif [[ -f "${SCRIPT_DIR}/install-device-support.sh" ]]; then
    bash "${SCRIPT_DIR}/install-device-support.sh" --root "$TARGET_ROOT"
    # Its getty drop-in autologins 'alarm' whatever --user says (and pacstrap
    # roots have no 'alarm'): the console keeps a normal login prompt.
    rm -rf "${TARGET_ROOT}/etc/systemd/system/getty@tty1.service.d"
fi

echo "=== [7/8] Installing device firmware ==="
if has_pkg asphalt-firmware; then
    echo "asphalt-firmware is installed as a package."
elif [[ -n "$FIRMWARE_SRC" && -d "$FIRMWARE_SRC" ]]; then
    echo "Installing device-specific firmware from $FIRMWARE_SRC..."
    mkdir -p "${TARGET_ROOT}/lib/firmware"
    
    # Copy asphalt firmware components
    for comp in ath11k cirrus novatek qca qcom awinic; do
        if [[ -d "${FIRMWARE_SRC}/${comp}" ]]; then
            mkdir -p "${TARGET_ROOT}/lib/firmware/${comp}"
            cp -r "${FIRMWARE_SRC}/${comp}/"* "${TARGET_ROOT}/lib/firmware/${comp}/" 2>/dev/null || true
        fi
    done
fi

echo "=== [8/8] Installing kernel modules ==="
if has_pkg linux-asphalt; then
    echo "Kernel modules come from the linux-asphalt package."
elif [[ -d "/lib/modules" ]]; then
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
LABEL=asphalt-arch             /              ext4    rw,noatime,x-systemd.growfs 0 1
# Factory sensor calibration is copied into /var/lib on first sensor startup.
/dev/disk/by-partlabel/persist /mnt/persist  ext4    ro,nofail       0       0
EOF
MICROSD_UID=$("${CHROOT[@]}" "$TARGET_ROOT" id -u "$USERNAME")
MICROSD_GID=$("${CHROOT[@]}" "$TARGET_ROOT" id -g "$USERNAME")
# File-manager re-mounts (udisks) follow this line to the microSD service's
# path; the symlink comes from 89-asphalt-microsd.rules (FAT-family cards only,
# the line carries uid/gid).
printf '/dev/disk/asphalt-microsd      /mnt/microsd   auto    noauto,nofail,noatime,nosuid,nodev,exec,uid=%s,gid=%s,umask=022,x-gvfs-show 0 0\n' \
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
if [[ "$DESKTOP" == none ]]; then
    echo "Autologin:        No (console login prompt on tty1)"
else
    echo "Autologin:        $([ $ENABLE_AUTOLOGIN -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
fi
echo "Desktop:          $DESKTOP$([ -n "$GREETER_INSTALL" ] && echo ' (touch greeter)')"
echo "sshd:             $([ -n "$SSH_KEY" ] && echo 'Enabled, key-only' || echo 'Not enabled')"
echo "==========================================================="
