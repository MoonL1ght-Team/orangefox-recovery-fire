#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
device_dir="$(cd "$script_dir/.." && pwd -P)"
board_config="$device_dir/BoardConfig.mk"
first_stage_fstab="$device_dir/recovery/root/first_stage_ramdisk/fstab.mt6768"
init_rc="$device_dir/recovery/root/init.recovery.mt6768.rc"
touch_loader="$device_dir/recovery/root/system/bin/init.fire.touch.sh"
touch_module="$device_dir/recovery/root/system/lib/modules/fire_touch_compat.ko"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

awk '{ sub(/\r$/, "") } $0 == \
  "TW_CUSTOM_CPU_TEMP_PATH := \"/sys/class/thermal/thermal_zone7/temp\"" \
  { found = 1 } END { exit !found }' "$board_config" || \
  fail 'CPU temperature path does not select battery thermal zone7'

for mount_point in /system_ext /vendor_dlkm /odm_dlkm /system_dlkm; do
  awk -v mount_point="$mount_point" \
    '$1 !~ /^#/ && $2 == mount_point && $0 ~ /first_stage_mount/ { found = 1 } END { exit !found }' \
    "$first_stage_fstab" || \
    fail "first-stage fstab does not mount $mount_point"
done

[[ -x "$touch_loader" ]] || fail "touch loader is missing or not executable"
bash -n "$touch_loader"
[[ -f "$touch_module" ]] || fail "touch compatibility module is missing"

grep -Fq 'mount -t erofs -o ro' "$touch_loader" || \
  fail 'touch loader does not mount vendor_dlkm read-only'
grep -Fq '/vendor_dlkm/lib/modules/xiaomi_touch.ko' "$touch_loader" || \
  fail 'touch loader does not load stock xiaomi_touch.ko'
grep -Fq '/system/lib/modules/fire_touch_compat.ko' "$touch_loader" || \
  fail 'touch loader does not load the recovery compatibility module'
grep -Fq '/vendor_dlkm/lib/modules/fts_8720.ko' "$touch_loader" || \
  fail 'touch loader does not load stock fts_8720.ko'
if awk '$1 !~ /^#/ && $0 ~ /(^|[[:space:]])modprobe([[:space:]]|$)/ \
  { found = 1 } END { exit !found }' "$touch_loader"; then
  fail 'touch loader must bypass the unsafe stock modprobe dependency chain'
fi

awk '
  $1 !~ /^#/ && /xiaomi_touch\.ko/ && !xiaomi { xiaomi = NR }
  $1 !~ /^#/ && /fire_touch_compat\.ko/ && !compat { compat = NR }
  $1 !~ /^#/ && /fts_8720\.ko/ && !fts { fts = NR }
  END { exit !(xiaomi && compat && fts && xiaomi < compat && compat < fts) }
' "$touch_loader" || fail 'touch modules are not loaded in the proven live-test order'

grep -Eq '^service fire-touch-loader /system/bin/init\.fire\.touch\.sh$' "$init_rc" || \
  fail 'recovery init does not declare the fire touch loader service'
grep -Eq '^[[:space:]]+start fire-touch-loader$' "$init_rc" || \
  fail 'recovery init does not start the fire touch loader service'

printf 'PASS: fire recovery runtime device-tree contract\n'
