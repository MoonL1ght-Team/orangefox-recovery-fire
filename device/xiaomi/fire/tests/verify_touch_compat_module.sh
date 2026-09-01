#!/usr/bin/env bash
set -Eeuo pipefail

module="${1:-}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -f "$module" ]] || fail "touch compatibility module is missing: $module"

expected_symbols=(
  ps_enable_register_notifier
  tpd_notifier_call_chain
)

for symbol in "${expected_symbols[@]}"; do
  nm -g --defined-only "$module" 2>/dev/null \
    | awk '{ print $NF }' \
    | grep -Fqx "$symbol" \
    || fail "module does not export $symbol"
done

depends="$(modinfo -F depends "$module")"
[[ -z "$depends" ]] || fail "module has unexpected dependencies: $depends"

vermagic="$(modinfo -F vermagic "$module")"
expected_vermagic='6.6.58-android15-8-g33c1ba9ffede-4k SMP preempt mod_unload modversions aarch64'
[[ "$vermagic" == "$expected_vermagic" ]] \
  || fail "module vermagic mismatch: $vermagic"

# The values are little-endian encodings of the two CRCs required by the
# proprietary FocalTech consumer: 0xdae3234b and 0x2bada41f.
crc_bytes="$(readelf -x __kcrctab_gpl "$module" 2>/dev/null \
  | awk '$1 ~ /^0x/ { printf "%s%s", $2, $3 }')"
[[ "$crc_bytes" == '4b23e3da1fa4ad2b' ]] || \
  fail "module export CRCs do not match fts_8720.ko: $crc_bytes"

printf 'PASS: fire recovery touch compatibility module ABI\n'
