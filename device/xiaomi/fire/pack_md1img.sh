#!/usr/bin/env bash
set -Eeuo pipefail

readonly STOCK_MD1IMG_SHA256='61bd3311ba922dd4ec28cb9a918cd53c20196586da94ea546faad6955fa07e42'
readonly STOCK_EMBEDDED_VENDOR_BOOT_SHA256='49cb03f3eea919bbcb72ac6a118e70cabbbc03a552cb6016ae673209280f37c0'
readonly MD1IMG_SIZE=$((0x08000000))
readonly VENDOR_BOOT_OFFSET=$((0x03f00000))
readonly VENDOR_BOOT_SIZE=$((0x04000000))
readonly VENDOR_BOOT_END=$((VENDOR_BOOT_OFFSET + VENDOR_BOOT_SIZE))

die() {
  printf 'fire md1img pack: ERROR: %s\n' "$*" >&2
  exit 1
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

stock_md1img="${1:-}"
vendor_boot="${2:-}"
output="${3:-}"

[[ -f "$stock_md1img" ]] || die "missing stock md1img: $stock_md1img"
[[ -f "$vendor_boot" ]] || die "missing vendor_boot: $vendor_boot"
[[ -n "$output" ]] || die 'missing output path'
[[ "$output" != "$stock_md1img" ]] || die 'output must not overwrite stock md1img'
[[ "$output" != "$vendor_boot" ]] || die 'output must not overwrite vendor_boot'

stock_size="$(stat -c %s "$stock_md1img")"
[[ "$stock_size" == "$MD1IMG_SIZE" ]] ||
  die "stock md1img size is $stock_size, expected $MD1IMG_SIZE"
stock_hash="$(sha256_of "$stock_md1img")"
[[ "$stock_hash" == "$STOCK_MD1IMG_SHA256" ]] ||
  die "stock md1img SHA-256 mismatch: $stock_hash"

embedded_stock_hash="$(dd if="$stock_md1img" bs=1M skip=63 count=64 status=none | sha256sum | awk '{print $1}')"
[[ "$embedded_stock_hash" == "$STOCK_EMBEDDED_VENDOR_BOOT_SHA256" ]] ||
  die "embedded stock vendor_boot SHA-256 mismatch: $embedded_stock_hash"

vendor_boot_size="$(stat -c %s "$vendor_boot")"
[[ "$vendor_boot_size" == "$VENDOR_BOOT_SIZE" ]] ||
  die "vendor_boot size is $vendor_boot_size, expected $VENDOR_BOOT_SIZE"
[[ "$(dd if="$vendor_boot" bs=1 count=8 status=none)" == 'VNDRBOOT' ]] ||
  die 'vendor_boot magic is not VNDRBOOT'
header_version="$(od -An -tu4 -j 8 -N 4 "$vendor_boot" | tr -d '[:space:]')"
[[ "$header_version" == 3 ]] ||
  die "vendor_boot header version is $header_version, expected 3"

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
tmp_output="$(mktemp "$output_dir/.fire-md1img.XXXXXX")"
trap 'rm -f "$tmp_output"' EXIT

cp --reflink=auto --sparse=always "$stock_md1img" "$tmp_output"
dd if="$vendor_boot" of="$tmp_output" bs=1M seek=63 count=64 \
  conv=notrunc,fsync status=none

final_size="$(stat -c %s "$tmp_output")"
[[ "$final_size" == "$MD1IMG_SIZE" ]] ||
  die "output size is $final_size, expected $MD1IMG_SIZE"
cmp -n "$VENDOR_BOOT_OFFSET" "$stock_md1img" "$tmp_output" >/dev/null ||
  die 'modem prefix changed'
cmp -s \
  <(dd if="$stock_md1img" bs=1M skip=127 status=none) \
  <(dd if="$tmp_output" bs=1M skip=127 status=none) ||
  die 'md1img tail changed'
cmp -s \
  <(dd if="$tmp_output" bs=1M skip=63 count=64 status=none) \
  "$vendor_boot" || die 'embedded vendor_boot differs from input'

chmod --reference="$stock_md1img" "$tmp_output"
mv -f "$tmp_output" "$output"
trap - EXIT

printf '%s  %s\n' "$(sha256_of "$output")" "$output"
printf 'fire md1img pack: preserved bytes [0, 0x03f00000) and [0x07f00000, 0x08000000)\n'
