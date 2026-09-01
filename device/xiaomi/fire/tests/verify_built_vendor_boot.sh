#!/usr/bin/env bash
set -Eeuo pipefail

readonly STOCK_VENDOR_BOOT_SHA256='ab3bed8ad89b726419b135f95e3eb2a79093c6af126efb7aeb7389b22d8443eb'
readonly STOCK_DTB_SHA256='34335f9afe4679cf8a039e46d07f43b2e090ce628d0dd43d02ad38155ee531f2'
readonly VENDOR_BOOT_PARTITION_SIZE='67108864'
readonly STOCK_MODULE_COUNT='167'
readonly STOCK_AVB_SALT='6dbd8bb2a861c4b7d30bdbe189899ba7a4d9756793f17a84b8766973c0fd0d15'
readonly STOCK_FINGERPRINT='Redmi/vnd_fire/fire:15/AP3A.240905.015.A2/OS2.0.208.0.VMXMIXM:user/release-keys'

die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
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
        printf 'file     %s  %s\n' \
          "$(sha256sum "$path" | awk '{print $1}')" "$path"
      fi
    done < <(find lib/modules \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
  )
}

image="${1:-}"
stock="${2:-${FOX_STOCK_VENDOR_BOOT:-}}"
[[ -f "$image" ]] || die "built vendor_boot image is missing: $image"
[[ -f "$stock" ]] || die "stock vendor_boot image is missing: $stock"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/../../../.." && pwd -P)"
magiskboot="${MAGISKBOOT:-$source_root/vendor/recovery/tools/magiskboot}"
avbtool="${AVBTOOL:-$source_root/external/avb/avbtool.py}"
[[ -x "$magiskboot" ]] || die "host magiskboot is unavailable: $magiskboot"
[[ -f "$avbtool" ]] || die "avbtool is unavailable: $avbtool"
if [[ -x "$avbtool" ]]; then
  avbtool_command=("$avbtool")
else
  avbtool_command=(python3 "$avbtool")
fi

stock_hash="$(sha256sum "$stock" | awk '{print $1}')"
[[ "$stock_hash" == "$STOCK_VENDOR_BOOT_SHA256" ]] || \
  die "stock vendor_boot SHA-256 mismatch: $stock_hash"

image_size="$(stat -c %s "$image")"
[[ "$image_size" == "$VENDOR_BOOT_PARTITION_SIZE" ]] || \
  die "image size is $image_size, expected $VENDOR_BOOT_PARTITION_SIZE"
cmp -s "$image" "$stock" && die 'built image is identical to stock; OrangeFox was not overlaid'

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/verify-fire-vendor-boot.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/stock/root" "$tmp_dir/final/root" "$tmp_dir/avb"
cp -f "$stock" "$tmp_dir/stock/vendor_boot.img"
cp -f "$image" "$tmp_dir/final/vendor_boot.img"
cp -f "$image" "$tmp_dir/avb/vendor_boot.img"

for kind in stock final; do
  (
    cd "$tmp_dir/$kind"
    "$magiskboot" unpack vendor_boot.img > unpack.log 2>&1
    [[ -f ramdisk.cpio && -f dtb ]] || exit 20
  ) || die "cannot unpack $kind vendor_boot"
  (
    cd "$tmp_dir/$kind/root"
    "$magiskboot" cpio ../ramdisk.cpio extract > ../cpio-extract.log 2>&1
  ) || die "cannot extract $kind vendor ramdisk"
done

grep -q 'HEADER_VER[[:space:]]*\[3\]' "$tmp_dir/final/unpack.log" || \
  die 'final vendor_boot is not header v3'
grep -q 'PAGESIZE[[:space:]]*\[4096\]' "$tmp_dir/final/unpack.log" || \
  die 'final vendor_boot page size is not 4096'
grep -q 'CMDLINE[[:space:]]*\[bootopt=64S3,32N2,64N2\]' \
  "$tmp_dir/final/unpack.log" || die 'final vendor cmdline differs from stock'
grep -q 'RAMDISK_FMT[[:space:]]*\[lz4_legacy\]' "$tmp_dir/final/unpack.log" || \
  die 'final vendor ramdisk is not legacy LZ4'

final_dtb_hash="$(sha256sum "$tmp_dir/final/dtb" | awk '{print $1}')"
[[ "$final_dtb_hash" == "$STOCK_DTB_SHA256" ]] || \
  die "final DTB SHA-256 mismatch: $final_dtb_hash"
cmp -s "$tmp_dir/stock/dtb" "$tmp_dir/final/dtb" || \
  die 'final DTB is not byte-for-byte identical to stock'

module_manifest "$tmp_dir/stock/root" > "$tmp_dir/stock-modules.sha256"
module_manifest "$tmp_dir/final/root" > "$tmp_dir/final-modules.sha256"
module_count="$(wc -l < "$tmp_dir/final-modules.sha256")"
[[ "$module_count" == "$STOCK_MODULE_COUNT" ]] || \
  die "final module count is $module_count, expected $STOCK_MODULE_COUNT"
cmp -s "$tmp_dir/stock-modules.sha256" "$tmp_dir/final-modules.sha256" || \
  die 'final stock module set or contents changed'
module_tree_manifest "$tmp_dir/stock/root" > "$tmp_dir/stock-module-tree.manifest"
module_tree_manifest "$tmp_dir/final/root" > "$tmp_dir/final-module-tree.manifest"
cmp -s "$tmp_dir/stock-module-tree.manifest" \
  "$tmp_dir/final-module-tree.manifest" || \
  die 'final stock module metadata or contents changed'

# The stock first-stage fstab maps and mounts system_ext plus all three DLKM
# partitions. Replacing it with the older device-tree copy leaves vendor_dlkm
# unmapped in recovery, so the stock touch stack can never be loaded.
stock_first_stage_fstab="$tmp_dir/stock/root/first_stage_ramdisk/fstab.mt6768"
final_first_stage_fstab="$tmp_dir/final/root/first_stage_ramdisk/fstab.mt6768"
[[ -f "$stock_first_stage_fstab" ]] || die 'stock first-stage fstab is missing'
[[ -f "$final_first_stage_fstab" ]] || die 'final first-stage fstab is missing'
cmp -s "$stock_first_stage_fstab" "$final_first_stage_fstab" || \
  die 'final first-stage fstab is not byte-for-byte identical to stock'

if [[ ! -x "$tmp_dir/final/root/system/bin/recovery" && \
      ! -x "$tmp_dir/final/root/sbin/recovery" ]]; then
  die 'OrangeFox recovery executable is absent from the final ramdisk'
fi

# The stock Android 15 recovery fragments use VINTF schema 8.0 and declare
# device manifests below /system. OrangeFox 12.1 ships libvintf 4.0, which
# rejects them and prevents hwservicemanager from serving Keymaster to
# keystore2. The AIDL recovery HALs do not require these declarations here.
for fragment in \
  android.hardware.boot-service.mtk.xml \
  android.hardware.fastboot-service.example.xml \
  android.hardware.health-service.example.xml; do
  [[ ! -e "$tmp_dir/final/root/system/etc/vintf/manifest/$fragment" ]] || \
    die "incompatible stock VINTF fragment remains: $fragment"
done

# Recovery's HIDL BootControl reads the misc block-device path from this
# fstab. All four physical entries must use the ueventd-created stable by-name
# directory rather than the absent legacy /platform/bootdevice alias.
recovery_fstab="$tmp_dir/final/root/system/etc/recovery.fstab"
[[ -f "$recovery_fstab" ]] || die 'final recovery.fstab is missing'
while read -r mount_point partition; do
  actual_source="$(awk -v mount_point="$mount_point" \
    '$1 !~ /^#/ && $2 == mount_point { print $1; exit }' "$recovery_fstab")"
  expected_source="/dev/block/by-name/$partition"
  [[ "$actual_source" == "$expected_source" ]] || \
    die "$mount_point source is '$actual_source', expected '$expected_source'"
done <<'EOF'
/data userdata
/metadata md_udc
/misc misc
/boot boot
EOF

(
  cd "$tmp_dir/avb"
  "${avbtool_command[@]}" verify_image --image vendor_boot.img > verify.log
  "${avbtool_command[@]}" info_image --image vendor_boot.img > info.log
) || die 'AVB footer verification failed'
grep -q 'Partition Name:[[:space:]]*vendor_boot' "$tmp_dir/avb/info.log" || \
  die 'AVB descriptor does not target vendor_boot'
grep -q '^Algorithm:[[:space:]]*NONE$' "$tmp_dir/avb/info.log" || \
  die 'AVB algorithm is not NONE'
grep -q 'Hash Algorithm:[[:space:]]*sha256' "$tmp_dir/avb/info.log" || \
  die 'AVB hash algorithm is not sha256'
grep -q "Salt:[[:space:]]*$STOCK_AVB_SALT" "$tmp_dir/avb/info.log" || \
  die 'AVB salt differs from stock'
fingerprint_line="Prop: com.android.build.vendor_boot.fingerprint -> '$STOCK_FINGERPRINT'"
fingerprint_count="$(grep -F -c "$fingerprint_line" "$tmp_dir/avb/info.log")"
[[ "$fingerprint_count" == 1 ]] || \
  die "expected one exact stock fingerprint property, found $fingerprint_count"

printf 'PASS: stock-preserving fire OrangeFox vendor_boot\n'
printf 'SHA-256: %s\n' "$(sha256sum "$image" | awk '{print $1}')"
printf 'Preserved: stock DTB and %s stock modules\n' "$STOCK_MODULE_COUNT"
