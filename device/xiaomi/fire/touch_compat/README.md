# fire recovery touch compatibility module

`fire_touch_compat.ko` supplies the two proximity-notifier symbols required by
the stock `fts_8720.ko` without loading the incompatible SCP/sensor dependency
chain in recovery. Both hooks are intentionally inert; touch input itself is
still handled by the unmodified stock FocalTech module from `vendor_dlkm`.

The checked-in prebuilt targets the pristine fire GKI release
`6.6.58-android15-8-g33c1ba9ffede-4k`. Its exported symbol CRCs are verified by
`tests/verify_touch_compat_module.sh` against the proprietary consumer ABI.
