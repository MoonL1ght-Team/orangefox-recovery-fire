#!/system/bin/sh

# Load only the recovery-relevant part of the stock fire touch stack. Using
# modprobe here also starts the SCP, sensor, modem and thermal dependency chain;
# that conflicts with the generic GKI scpsys driver already active in recovery.

log_touch()
{
    echo "fire-touch: $*" > /dev/kmsg 2>/dev/null
}

module_loaded()
{
    grep -q "^$1 " /proc/modules
}

slot_suffix="$(getprop ro.boot.slot_suffix)"
vendor_dlkm_block="/dev/block/mapper/vendor_dlkm${slot_suffix}"

attempt=0
while [ ! -e "$vendor_dlkm_block" ] && [ "$attempt" -lt 100 ]; do
    usleep 100000
    attempt=$((attempt + 1))
done

if [ ! -e "$vendor_dlkm_block" ]; then
    log_touch "missing $vendor_dlkm_block"
    exit 1
fi

mkdir -p /vendor_dlkm
if ! mountpoint /vendor_dlkm >/dev/null 2>&1; then
    mount -t erofs -o ro "$vendor_dlkm_block" /vendor_dlkm || {
        log_touch "cannot mount $vendor_dlkm_block read-only"
        exit 1
    }
fi

# miev is part of the stock vendor ramdisk module set and is normally loaded by
# first-stage init. Wait for it rather than pulling in unrelated DLKM modules.
attempt=0
while ! module_loaded miev && [ "$attempt" -lt 100 ]; do
    usleep 100000
    attempt=$((attempt + 1))
done

module_loaded miev || {
    log_touch "miev provider did not become ready"
    exit 1
}

module_loaded xiaomi_touch || \
    insmod /vendor_dlkm/lib/modules/xiaomi_touch.ko || {
        log_touch "cannot load xiaomi_touch.ko"
        exit 1
    }

module_loaded fire_touch_compat || \
    insmod /system/lib/modules/fire_touch_compat.ko || {
        log_touch "cannot load fire_touch_compat.ko"
        exit 1
    }

module_loaded fts_8720 || \
    insmod /vendor_dlkm/lib/modules/fts_8720.ko || {
        log_touch "cannot load fts_8720.ko"
        exit 1
    }

log_touch "FT8725 input stack loaded"
