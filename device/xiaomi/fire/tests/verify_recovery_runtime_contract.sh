#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
device_dir="$(cd "$script_dir/.." && pwd -P)"
board_config="$device_dir/BoardConfig.mk"
first_stage_fstab="$device_dir/recovery/root/first_stage_ramdisk/fstab.mt6768"

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

printf 'PASS: fire recovery runtime device-tree contract\n'
