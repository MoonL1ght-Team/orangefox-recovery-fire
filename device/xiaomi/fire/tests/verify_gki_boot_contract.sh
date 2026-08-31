#!/usr/bin/env bash
set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
device_dir="$(cd "$script_dir/.." && pwd -P)"
source_root="$(cd "$device_dir/../../.." && pwd -P)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_var() {
  local variable="$1"
  local expected="$2"
  local actual
  actual="$(get_build_var "$variable")"
  if [[ "$actual" != "$expected" ]]; then
    fail "$variable expected '$expected', got '$actual'"
  fi
}

expect_empty_var() {
  local variable="$1"
  local actual
  actual="$(get_build_var "$variable")"
  if [[ -n "$actual" ]]; then
    fail "$variable must be empty, got '$actual'"
  fi
}

expect_contains_var() {
  local variable="$1"
  local expected="$2"
  local actual
  actual="$(get_build_var "$variable")"
  [[ "$actual" == *"$expected"* ]] || \
    fail "$variable does not contain '$expected': $actual"
}

expect_word_var() {
  local variable="$1"
  local expected="$2"
  local actual
  actual=" $(get_build_var "$variable") "
  [[ "$actual" == *" $expected "* ]] || \
    fail "$variable does not contain word '$expected': $actual"
}

cd "$source_root"
export ALLOW_MISSING_DEPENDENCIES=true
export FOX_BUILD_DEVICE=fire
export LC_ALL=C
set +e
source build/envsetup.sh >/dev/null
set -e
lunch twrp_fire-eng >/dev/null

expect_var BOARD_BOOT_HEADER_VERSION 3
expect_var BOARD_BOOTIMG_HEADER_VERSION 3
expect_var BOARD_BOOTIMAGE_PARTITION_SIZE 134217728
expect_var BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE 67108864
expect_word_var AB_OTA_PARTITIONS vendor_boot
expect_var BOARD_USES_GENERIC_KERNEL_IMAGE true
expect_var BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT true
expect_empty_var BOARD_USES_RECOVERY_AS_BOOT
expect_empty_var BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT
expect_var TARGET_NO_RECOVERY true
expect_var BOARD_RAMDISK_USE_LZ4 true
expect_var BOARD_KERNEL_BASE 0x00000000
expect_var BOARD_KERNEL_PAGESIZE 4096
expect_var BOARD_KERNEL_CMDLINE bootopt=64S3,32N2,64N2
expect_contains_var BOARD_MKBOOTIMG_ARGS '--header_version 3'
expect_contains_var BOARD_MKBOOTIMG_ARGS '--kernel_offset 0x40080000'
expect_contains_var BOARD_MKBOOTIMG_ARGS '--ramdisk_offset 0x47c80000'
expect_contains_var BOARD_MKBOOTIMG_ARGS '--tags_offset 0x4bc80000'
expect_contains_var BOARD_MKBOOTIMG_ARGS '--dtb_offset 0x4bc80000'
expect_empty_var TARGET_PREBUILT_DTB
expect_var BOARD_INCLUDE_DTB_IN_BOOTIMG true
expect_empty_var OF_SUPPORT_ALL_BLOCK_OTA_UPDATES
expect_contains_var BOARD_AVB_VENDOR_BOOT_ADD_HASH_FOOTER_ARGS \
  '--salt 6dbd8bb2a861c4b7d30bdbe189899ba7a4d9756793f17a84b8766973c0fd0d15'
expect_contains_var BOARD_AVB_VENDOR_BOOT_ADD_HASH_FOOTER_ARGS \
  'com.android.build.vendor_boot.fingerprint:Redmi/vnd_fire/fire:15/AP3A.240905.015.A2/OS2.0.208.0.VMXMIXM:user/release-keys'

[[ "${FOX_VENDOR_BOOT_RECOVERY:-}" == 1 ]] || \
  fail "FOX_VENDOR_BOOT_RECOVERY expected '1', got '${FOX_VENDOR_BOOT_RECOVERY:-}'"
[[ "${FOX_INSTALLER_VENDOR_BOOT_RAMDISK_INSTALL:-}" == 0 ]] || \
  fail "FOX_INSTALLER_VENDOR_BOOT_RAMDISK_INSTALL expected '0', got '${FOX_INSTALLER_VENDOR_BOOT_RAMDISK_INSTALL:-}'"

callback_path="${FOX_LOCAL_CALLBACK_SCRIPT:-}"
[[ -n "$callback_path" ]] || fail 'FOX_LOCAL_CALLBACK_SCRIPT is empty'
if [[ "$callback_path" != /* ]]; then
  callback_path="$source_root/$callback_path"
fi
[[ -x "$callback_path" ]] || fail "vendor_boot callback is missing or not executable: $callback_path"
bash -n "$callback_path"
grep -q "STOCK_MODULE_COUNT='167'" "$callback_path" || \
  fail 'vendor_boot callback does not enforce the 167-module stock contract'
grep -q 'stock-module-tree.manifest' "$callback_path" || \
  fail 'vendor_boot callback does not preserve stock module metadata'

stock_vendor_boot="${FOX_STOCK_VENDOR_BOOT:-}"
[[ -f "$stock_vendor_boot" ]] || fail "stock vendor_boot input is missing: $stock_vendor_boot"
stock_vendor_boot_hash="$(sha256sum "$stock_vendor_boot" | awk '{print $1}')"
[[ "$stock_vendor_boot_hash" == 'ab3bed8ad89b726419b135f95e3eb2a79093c6af126efb7aeb7389b22d8443eb' ]] || \
  fail "stock vendor_boot hash mismatch: $stock_vendor_boot_hash"

stock_dtb_dir="$(get_build_var BOARD_PREBUILT_DTBIMAGE_DIR)"
[[ -n "$stock_dtb_dir" ]] || fail 'BOARD_PREBUILT_DTBIMAGE_DIR is empty'
if [[ "$stock_dtb_dir" != /* ]]; then
  stock_dtb_dir="$source_root/$stock_dtb_dir"
fi
stock_dtb="$stock_dtb_dir/fire-stock.dtb"
[[ -f "$stock_dtb" ]] || fail "stock DTB input is missing: $stock_dtb"
stock_dtb_hash="$(sha256sum "$stock_dtb" | awk '{print $1}')"
[[ "$stock_dtb_hash" == '34335f9afe4679cf8a039e46d07f43b2e090ce628d0dd43d02ad38155ee531f2' ]] || \
  fail "stock DTB hash mismatch: $stock_dtb_hash"

kernel_path="$(get_build_var TARGET_PREBUILT_KERNEL)"
[[ -n "$kernel_path" ]] || fail 'TARGET_PREBUILT_KERNEL is empty'
if [[ "$kernel_path" != /* ]]; then
  kernel_path="$source_root/$kernel_path"
fi
[[ -f "$kernel_path" ]] || fail "kernel payload is missing: $kernel_path"
gzip -t "$kernel_path"

compressed_hash="$(sha256sum "$kernel_path" | awk '{print $1}')"
[[ "$compressed_hash" == '3f264a4fa9c848fca5eb014f45a71db31588fd62dbdd8e2c1cf2f0e018b780a8' ]] || \
  fail "compressed kernel hash mismatch: $compressed_hash"

raw_hash="$(gzip -dc "$kernel_path" | sha256sum | awk '{print $1}')"
[[ "$raw_hash" == 'a8d83641a9596bc40c6d6acaeb9c1271c5c9809cc4ff797e40907f58b2db7ffd' ]] || \
  fail "raw kernel hash mismatch: $raw_hash"

module_path="$(find "$device_dir" -type f -name '*.ko' -print -quit)"
[[ -z "$module_path" ]] || fail "kernel module bundled in device tree: $module_path"

printf 'PASS: fire OrangeFox GKI vendor_boot contract\n'
