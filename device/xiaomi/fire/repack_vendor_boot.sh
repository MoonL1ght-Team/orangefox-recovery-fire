#!/usr/bin/env bash
set -Eeuo pipefail

readonly STOCK_VENDOR_BOOT_SHA256='ab3bed8ad89b726419b135f95e3eb2a79093c6af126efb7aeb7389b22d8443eb'
readonly STOCK_DTB_SHA256='34335f9afe4679cf8a039e46d07f43b2e090ce628d0dd43d02ad38155ee531f2'
readonly VENDOR_BOOT_PARTITION_SIZE='67108864'
readonly STOCK_AVB_SALT='6dbd8bb2a861c4b7d30bdbe189899ba7a4d9756793f17a84b8766973c0fd0d15'
readonly STOCK_FINGERPRINT='Redmi/vnd_fire/fire:15/AP3A.240905.015.A2/OS2.0.208.0.VMXMIXM:user/release-keys'
readonly STOCK_MODULE_COUNT='167'

die() {
  printf 'fire vendor_boot repack: ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

module_manifest() {
  local root="$1"
  (
    cd "$root"
    find . -type f -name '*.ko' -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 -r sha256sum
  )
}

module_tree_manifest() {
  local root="$1"
  (
    cd "$root"
    [[ -d lib/modules ]] || exit 1
    while IFS= read -r -d '' path; do
      if [[ -L "$path" ]]; then
        printf 'symlink  %s -> %s\n' "$path" "$(readlink "$path")"
      else
        printf 'file     %s  %s\n' "$(sha256_of "$path")" "$path"
      fi
    done < <(find lib/modules \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
  )
}

working_dir="${1:-}"
phase="${2:-}"

# OrangeFox calls the hook once while constructing the recovery root and once
# after recovery.img has been copied into the installer staging directory.
if [[ "$phase" == '--first-call' ]]; then
  vendor_ramdisk_out="${TARGET_VENDOR_RAMDISK_OUT:-}"
  [[ -n "$vendor_ramdisk_out" ]] || \
    die 'TARGET_VENDOR_RAMDISK_OUT is empty during first callback'
  mkdir -p "$vendor_ramdisk_out"
  printf 'fire vendor_boot repack: prepared vendor ramdisk directory: %s\n' \
    "$vendor_ramdisk_out"
  exit 0
fi
[[ "$phase" == '--last-call' ]] || die "unexpected callback phase: $phase"
[[ -d "$working_dir" ]] || die "invalid installer staging directory: $working_dir"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/../../.." && pwd -P)"
magiskboot="$source_root/vendor/recovery/tools/magiskboot"
mkbootfs="${MKBOOTFS:-$source_root/vendor/recovery/tools/mkbootfs}"
avbtool="$source_root/external/avb/avbtool.py"
stock_vendor_boot="${FOX_STOCK_VENDOR_BOOT:-}"
generated_vendor_boot="$working_dir/recovery.img"

[[ -x "$magiskboot" ]] || die "host magiskboot is not executable: $magiskboot"
[[ -x "$mkbootfs" ]] || die "host mkbootfs is not executable: $mkbootfs"
require_file "$avbtool"
require_file "$stock_vendor_boot"
require_file "$generated_vendor_boot"

actual_stock_hash="$(sha256_of "$stock_vendor_boot")"
[[ "$actual_stock_hash" == "$STOCK_VENDOR_BOOT_SHA256" ]] || \
  die "stock vendor_boot SHA-256 mismatch: $actual_stock_hash"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/fire-vendor-boot.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/stock/root" "$tmp_dir/orangefox/root" \
  "$tmp_dir/merged/root" "$tmp_dir/final" "$tmp_dir/avb-check"

cp -f "$stock_vendor_boot" "$tmp_dir/stock/vendor_boot.img"
cp -f "$generated_vendor_boot" "$tmp_dir/orangefox/vendor_boot.img"

(
  cd "$tmp_dir/stock"
  "$magiskboot" unpack vendor_boot.img > unpack.log 2>&1
  require_file ramdisk.cpio
  require_file dtb
)
(
  cd "$tmp_dir/stock/root"
  "$magiskboot" cpio ../ramdisk.cpio extract > ../cpio-extract.log 2>&1
)

(
  cd "$tmp_dir/orangefox"
  "$magiskboot" unpack vendor_boot.img > unpack.log 2>&1
  require_file ramdisk.cpio
)
(
  cd "$tmp_dir/orangefox/root"
  "$magiskboot" cpio ../ramdisk.cpio extract > ../cpio-extract.log 2>&1
)

grep -q 'HEADER_VER[[:space:]]*\[3\]' "$tmp_dir/stock/unpack.log" || \
  die 'stock vendor_boot is not header v3'
grep -q 'PAGESIZE[[:space:]]*\[4096\]' "$tmp_dir/stock/unpack.log" || \
  die 'stock vendor_boot page size is not 4096'
grep -q 'RAMDISK_FMT[[:space:]]*\[lz4_legacy\]' "$tmp_dir/stock/unpack.log" || \
  die 'stock vendor ramdisk is not legacy LZ4'

actual_dtb_hash="$(sha256_of "$tmp_dir/stock/dtb")"
[[ "$actual_dtb_hash" == "$STOCK_DTB_SHA256" ]] || \
  die "stock DTB SHA-256 mismatch: $actual_dtb_hash"

module_manifest "$tmp_dir/stock/root" > "$tmp_dir/stock-modules.sha256"
stock_module_count="$(wc -l < "$tmp_dir/stock-modules.sha256")"
[[ "$stock_module_count" == "$STOCK_MODULE_COUNT" ]] || \
  die "expected $STOCK_MODULE_COUNT stock modules, found $stock_module_count"
module_tree_manifest "$tmp_dir/stock/root" > "$tmp_dir/stock-module-tree.manifest"

orangefox_module="$(find "$tmp_dir/orangefox/root" -type f -name '*.ko' -print -quit)"
[[ -z "$orangefox_module" ]] || \
  die "OrangeFox ramdisk unexpectedly contains a kernel module: $orangefox_module"

# Overlay the OrangeFox root on the extracted stock root before archiving. This
# avoids duplicate cpio entries (and their size cost) while leaving stock-only
# files in place. Proprietary modules remain byte-for-byte identical and are
# verified again after repacking.
rsync -aH --numeric-ids "$tmp_dir/stock/root/" "$tmp_dir/merged/root/"
rsync -aH --numeric-ids "$tmp_dir/orangefox/root/" "$tmp_dir/merged/root/"

# OrangeFox may generate modules.load/modules.dep metadata even when it ships no
# .ko payload. Preserve the complete stock module directory so dependency and
# load-order metadata cannot be silently replaced by the recovery overlay.
rm -rf "$tmp_dir/merged/root/lib/modules"
mkdir -p "$tmp_dir/merged/root/lib/modules"
rsync -aH --numeric-ids "$tmp_dir/stock/root/lib/modules/" \
  "$tmp_dir/merged/root/lib/modules/"
target_out="${TARGET_OUT:-$source_root/out/target/product/fire/system}"
"$mkbootfs" -d "$target_out" "$tmp_dir/merged/root" \
  > "$tmp_dir/stock/ramdisk.cpio"

(
  cd "$tmp_dir/stock"
  "$magiskboot" repack vendor_boot.img "$tmp_dir/final/vendor_boot.img"
)

# magiskboot preserves the old footer verbatim. Recompute its hash descriptor
# after changing the ramdisk while retaining the stock salt and fingerprint.
python3 "$avbtool" erase_footer \
  --image "$tmp_dir/final/vendor_boot.img"
python3 "$avbtool" add_hash_footer \
  --image "$tmp_dir/final/vendor_boot.img" \
  --partition_size "$VENDOR_BOOT_PARTITION_SIZE" \
  --partition_name vendor_boot \
  --salt "$STOCK_AVB_SALT" \
  --prop "com.android.build.vendor_boot.fingerprint:$STOCK_FINGERPRINT"

cp -f "$tmp_dir/final/vendor_boot.img" "$tmp_dir/avb-check/vendor_boot.img"
(
  cd "$tmp_dir/avb-check"
  python3 "$avbtool" verify_image --image vendor_boot.img > avb-verify.log
)

(
  cd "$tmp_dir/final"
  "$magiskboot" unpack vendor_boot.img > unpack.log 2>&1
  require_file ramdisk.cpio
  require_file dtb
)
mkdir -p "$tmp_dir/final/root"
(
  cd "$tmp_dir/final/root"
  "$magiskboot" cpio ../ramdisk.cpio extract > ../cpio-extract.log 2>&1
)

grep -q 'HEADER_VER[[:space:]]*\[3\]' "$tmp_dir/final/unpack.log" || \
  die 'final vendor_boot is not header v3'
grep -q 'PAGESIZE[[:space:]]*\[4096\]' "$tmp_dir/final/unpack.log" || \
  die 'final vendor_boot page size is not 4096'
grep -q 'CMDLINE[[:space:]]*\[bootopt=64S3,32N2,64N2\]' \
  "$tmp_dir/final/unpack.log" || die 'final vendor cmdline differs from stock'
grep -q 'RAMDISK_FMT[[:space:]]*\[lz4_legacy\]' "$tmp_dir/final/unpack.log" || \
  die 'final vendor ramdisk is not legacy LZ4'

final_dtb_hash="$(sha256_of "$tmp_dir/final/dtb")"
[[ "$final_dtb_hash" == "$STOCK_DTB_SHA256" ]] || \
  die "final DTB SHA-256 mismatch: $final_dtb_hash"

module_manifest "$tmp_dir/final/root" > "$tmp_dir/final-modules.sha256"
cmp -s "$tmp_dir/stock-modules.sha256" "$tmp_dir/final-modules.sha256" || \
  die 'final stock module set or contents changed'
module_tree_manifest "$tmp_dir/final/root" > "$tmp_dir/final-module-tree.manifest"
cmp -s "$tmp_dir/stock-module-tree.manifest" \
  "$tmp_dir/final-module-tree.manifest" || \
  die 'final stock module metadata or contents changed'

final_size="$(stat -c %s "$tmp_dir/final/vendor_boot.img")"
[[ "$final_size" == "$VENDOR_BOOT_PARTITION_SIZE" ]] || \
  die "final image size is $final_size, expected $VENDOR_BOOT_PARTITION_SIZE"

# Replace both the ZIP payload and OrangeFox standalone/build outputs.
cp -f "$tmp_dir/final/vendor_boot.img" "$working_dir/recovery.img"
if [[ -n "${OUT:-}" ]]; then
  cp -f "$tmp_dir/final/vendor_boot.img" "$OUT/vendor_boot.img"
  if [[ -n "${FOX_OUT_NAME:-}" ]]; then
    cp -f "$tmp_dir/final/vendor_boot.img" "$OUT/$FOX_OUT_NAME.img"
  fi
fi

# Keep the optional header-v3 manual ramdisk payload consistent with the full
# image. The ZIP installer is explicitly configured to flash the full image.
(
  cd "$tmp_dir/final"
  rm -f ramdisk.cpio dtb
  "$magiskboot" unpack -n vendor_boot.img > /dev/null 2>&1
  require_file ramdisk.cpio
  cp -f ramdisk.cpio "$working_dir/ramdisk.cpio"
)

printf '%s  %s\n' "$(sha256_of "$working_dir/recovery.img")" \
  'recovery.img (stock-preserving vendor_boot)'
printf 'fire vendor_boot repack: preserved %s stock modules and stock DTB\n' \
  "$STOCK_MODULE_COUNT"
