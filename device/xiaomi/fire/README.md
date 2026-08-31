# OFRP Device Tree for Xiaomi Redmi 12

The Xiaomi Redmi 12 (codenamed _"fire"_) is an entry-level smartphone from Xiaomi.

It was announced and released in June 2023.

## Device specifications

| Feature                        | Specification                                                     |
| -----------------------------: | :---------------------------------------------------------------- |
| Chipset                        | Mediatek MT6769H Helio G88                                        |
| CPU                            | Octa-core (2x2.0 GHz Cortex-A75 & 6x1.8 GHz Cortex-A55)           |
| GPU                            | Mali-G52 MC2                                                      |
| Memory                         | 4GB / 6GB / 8GB RAM (LPDDR4X)                                     |
| Shipped OS                     | Android 13, MIUI 14                                               |
| Storage                        | 128GB / 256GB (eMMC 5.1)                                          |
| SIM                            | Hybrid Dual SIM (Nano-SIM, dual stand-by)                         |
| MicroSD                        | Up to 1TB                                                         |
| Battery                        | 5000mAh Li-Po (non-removable), 18W fast charge                    |
| Dimensions                     | 168.6 x 76.3 x 8.2 mm (6.64 x 3.00 x 0.32 in)                     |
| Display                        | 6.79", 1080 x 2460 pixels, IPS LCD, 90Hz (~396 ppi density)       |
| Rear Camera 1                  | 50 MP, f/1.8, (wide), PDAF                                        |
| Rear Camera 2                  | 8 MP, f/2.2, 120˚ (ultrawide)                                     |
| Rear Camera 3                  | 2 MP, f/2.4, (macro)                                              |
| Front Camera                   | 8 MP, f/2.1                                                       |
| Fingerprint                    | (side-mounted)                                                    |
| Sensors                        | accelerometer, compass                                            |

$~$

## Working features so far

### Blocking checks
- [X] Correct screen/recovery size
- [X] Working Touch, screen
- [X] Working slot switching
- [X] Backup to internal/microSD
- [X] Restore from internal/microSD
- [X] reboot to system
- [X] ADB

### Medium checks
- [X] update.zip sideload
- [X] UI colors (red/blue inversions)
- [X] Screen goes off and on
- [X] F2FS/EXT4 Support, exFAT/NTFS where supported
- [X] all important partitions listed in mount/backup lists
- [X] backup/restore to/from external (USB-OTG) storage
- [X] backup/restore to/from adb (https://gerrit.omnirom.org/#/c/15943/)
- [X] decrypt /data
- [X] Correct date

### Minor checks
- [X] MTP export
- [X] reboot to bootloader
- [X] reboot to recovery
- [X] poweroff
- [X] battery level
- [X] temperature
- [ ] ~~encrypted backups~~ (no option)
- [X] input devices via USB (USB-OTG) - keyboard, mouse and disks
- [ ] ~~USB mass storage export~~ (unavailable)
- [X] set brightness
- [X] vibrate
- [X] screenshot
- [X] partition SD card

$~$

## How to build

This branch targets the stable OrangeFox 12.1 source tree and Android boot
header v3. Recovery lives in `vendor_boot`; it is not a recovery-as-boot build.
The final image is repacked from an exact stock `vendor_boot.img` so the stock
DTB and all 167 proprietary kernel modules remain byte-for-byte unchanged.

Place the contents of this repository in the OrangeFox source root, then make
the verified stock input available outside Git:

```bash
export FOX_STOCK_VENDOR_BOOT=/absolute/path/to/stock/vendor_boot.img
sha256sum "$FOX_STOCK_VENDOR_BOOT"
```

The required stock SHA-256 is:

```text
ab3bed8ad89b726419b135f95e3eb2a79093c6af126efb7aeb7389b22d8443eb
```

Pinned build inputs and committed artifact hashes:

```text
GKI 6.6 raw Image:
a8d83641a9596bc40c6d6acaeb9c1271c5c9809cc4ff797e40907f58b2db7ffd

Deterministic gzip prebuilt/kernel:
3f264a4fa9c848fca5eb014f45a71db31588fd62dbdd8e2c1cf2f0e018b780a8

Stock vendor_boot DTB, prebuilt/stock-dtb/fire-stock.dtb:
34335f9afe4679cf8a039e46d07f43b2e090ce628d0dd43d02ad38155ee531f2
```

The raw kernel reports `6.6.58-android15-8-g70ca9d91bc7d-4k`. The complete
stock `vendor_boot.img` remains an external build input and is ignored by Git.

```bash
export ALLOW_MISSING_DEPENDENCIES=true
export FOX_BUILD_DEVICE=fire
export LC_ALL=C
source build/envsetup.sh
lunch twrp_fire-eng

# Verify the evaluated image contract before compiling.
bash device/xiaomi/fire/tests/verify_gki_boot_contract.sh

# Build vendor_boot, not boot or recovery.
mka adbd vendorbootimage
```

After the build, verify the full image before using it:

```bash
bash device/xiaomi/fire/tests/verify_built_vendor_boot.sh \
  out/target/product/fire/vendor_boot.img \
  "$FOX_STOCK_VENDOR_BOOT"
```

The OrangeFox ZIP is configured for full-image installation to
`vendor_boot_a` and `vendor_boot_b`. It does not install kernel modules or
modify `boot`, DTBO, or any DLKM partition. The kernel remains in the existing
GKI `boot` image.

## Credits

AntarcticShaurant TWRP Device tree: https://github.com/redmi-fire-devs/twrp_device_xiaomi_fire
## Device picture

![xiaomi-redmi-12-1](https://github.com/AntarticShaurant/android_device_xiaomi_fire/assets/109678650/bd593af4-92d4-4d5a-872d-e21bbb699a89)
