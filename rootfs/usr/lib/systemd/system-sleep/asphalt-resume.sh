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
printf '%s\n' "$phase" > /run/asphalt-sleep-state.tmp
mv /run/asphalt-sleep-state.tmp /run/asphalt-sleep-state

if [ "$1" = "pre" ]; then
    # stock use s2idle for DP-connected displays, deep for everything else
    sleep_mode=deep
    for status in /sys/class/drm/card*-DP-*/status; do
        [ -r "$status" ] || continue
        if [ "$(cat "$status" 2>/dev/null)" = "connected" ]; then
            sleep_mode=s2idle
            break
        fi
    done
    printf '%s\n' "$sleep_mode" > /sys/power/mem_sleep 2>/dev/null || true
fi

if [ "$1" = "post" ]; then
    # Restore ALSA UCM Speaker routes after DSP sleep
    /usr/bin/alsaucm -c hw:0 set _verb HiFi set _enadev Speaker 2>/dev/null || true

    # Queue display wake + backlight unblank after user.slice thaws.
    # Sleep hooks run while user.slice is frozen: do not contact its D-Bus
    # here or depend on a fixed delay to guess when it will be thawed.
    systemctl --no-block restart asphalt-resume-display.service

    # Rotation and the light proxy are restored by asphalt-suspend-sensors.service

    # Preserve each resume's IRQ in the journal before a later wake replaces it.
    WAKE_IRQ=$(cat /sys/power/pm_wakeup_irq 2>/dev/null) || WAKE_IRQ=unknown
    WAKE_IRQ=${WAKE_IRQ:-unknown}
    WAKE_SOURCE=$(awk -v irq="$WAKE_IRQ:" '$1 == irq {print; exit}' /proc/interrupts)
    printf '[WAKE] irq=%s source=%s\n' "$WAKE_IRQ" "${WAKE_SOURCE:-unavailable}"
fi
