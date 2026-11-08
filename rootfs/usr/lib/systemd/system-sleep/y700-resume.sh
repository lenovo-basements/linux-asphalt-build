#!/bin/sh
# Lenovo Legion Y700 (2023) / TB320FC / asphalt
# Post-Suspend Wake & Display Restoration Hook

if [ "$2" != "suspend" ]; then
    exit 0
fi

# Publish atomically: the power-key daemon must never read a partial marker.
case "$1" in
    pre) phase=sleeping ;;
    post) phase=awake ;;
    *) exit 0 ;;
esac
printf '%s\n' "$phase" > /run/y700-sleep-state.tmp
mv /run/y700-sleep-state.tmp /run/y700-sleep-state

if [ "$1" = "post" ]; then
    # Restore ALSA UCM Speaker routes after DSP sleep
    /usr/bin/alsaucm -c hw:0 set _verb HiFi set _enadev Speaker 2>/dev/null || true

    # 1. Unblank backlight power controller
    echo 0 > /sys/class/backlight/ktz8866-backlight/bl_power 2>/dev/null || true

    # 2. Ensure backlight level is visible
    CUR_B=$(cat /sys/class/backlight/ktz8866-backlight/brightness 2>/dev/null || echo 0)
    if [ "$CUR_B" -lt 164 ]; then
        echo 800 > /sys/class/backlight/ktz8866-backlight/brightness 2>/dev/null || true
    fi

    # 3. Queue a separate unit ordered after systemd-suspend.service.
    # Sleep hooks run while user.slice is frozen: do not contact its D-Bus
    # here or depend on a fixed delay to guess when it will be thawed.
    systemctl --no-block restart y700-resume-display.service

    # Rotation and the light proxy are restored by y700-suspend-sensors.service
    # after user.slice thaws, preserving services that were manually stopped.

    # Preserve each resume's IRQ in the journal before a later wake replaces it.
    WAKE_IRQ=$(cat /sys/power/pm_wakeup_irq 2>/dev/null) || WAKE_IRQ=unknown
    WAKE_IRQ=${WAKE_IRQ:-unknown}
    WAKE_SOURCE=$(awk -v irq="$WAKE_IRQ:" '$1 == irq {print; exit}' /proc/interrupts)
    printf '[WAKE] irq=%s source=%s\n' "$WAKE_IRQ" "${WAKE_SOURCE:-unavailable}"
fi
