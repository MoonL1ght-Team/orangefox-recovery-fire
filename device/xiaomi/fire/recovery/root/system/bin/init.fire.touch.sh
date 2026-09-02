#!/system/bin/sh

# Load only the stock DLKM modules required by recovery. Using the complete
# modules.load list would also start the SCP, sensor and modem stacks, which
# conflict with the generic GKI drivers already active in recovery.

log_touch()
{
    echo "fire-touch: $*" > /dev/kmsg 2>/dev/null
}

module_loaded()
{
    grep -q "^$1 " /proc/modules
}

load_required_module()
{
    module_name="$1"
    module_path="$2"

    module_loaded "$module_name" && return 0
    insmod "$module_path" && return 0

    log_touch "cannot load $module_path"
    return 1
}

load_performance_stack()
{
    load_required_module sspm_v1 /vendor_dlkm/lib/modules/sspm_v1.ko &&
    load_required_module mediatek_static_power /vendor_dlkm/lib/modules/mediatek_static_power.ko &&
    load_required_module Upower /vendor_dlkm/lib/modules/Upower.ko &&
    load_required_module fhctl /vendor_dlkm/lib/modules/fhctl.ko &&
    load_required_module mtk_cpuhp /lib/modules/mtk_cpuhp.ko &&
    load_required_module mtk_ppm_v3 /vendor_dlkm/lib/modules/mtk_ppm_v3.ko &&
    load_required_module CPU_DVFS /vendor_dlkm/lib/modules/CPU_DVFS.ko
}

load_flashlight_stack()
{
    load_required_module mtk_bp_thl /vendor_dlkm/lib/modules/mtk_bp_thl.ko &&
    load_required_module flashlight /vendor_dlkm/lib/modules/flashlight.ko &&
    load_required_module flashlights_aw3641e /vendor_dlkm/lib/modules/flashlights-aw3641e.ko
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

if load_performance_stack &&
   [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
    log_touch "CPU DVFS stack loaded"
else
    log_touch "CPU DVFS stack unavailable"
fi

if load_flashlight_stack &&
   [ -w /sys/class/leds/torch-light0/brightness ]; then
    log_touch "AW3641E flashlight stack loaded"
else
    log_touch "AW3641E flashlight stack unavailable"
fi

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
