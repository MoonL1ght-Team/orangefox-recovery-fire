# OrangeFox build configuration for Xiaomi Redmi 12 (fire).

_fox_device_path="device/xiaomi/fire"
_fox_top="$(gettop 2>/dev/null)"
if [ -n "$_fox_top" ] && [ -f "$_fox_top/$_fox_device_path/Magisk/Magisk-v28.0.zip" ]; then
  export FOX_USE_SPECIFIC_MAGISK_ZIP="$_fox_top/$_fox_device_path/Magisk/Magisk-v28.0.zip"
fi

if [ -n "$_fox_top" ]; then
  export FOX_LOCAL_CALLBACK_SCRIPT="$_fox_top/$_fox_device_path/repack_vendor_boot.sh"
  if [ -z "${FOX_STOCK_VENDOR_BOOT:-}" ] && \
     [ -f "$_fox_top/$_fox_device_path/prebuilt/stock/vendor_boot.img" ]; then
    export FOX_STOCK_VENDOR_BOOT="$_fox_top/$_fox_device_path/prebuilt/stock/vendor_boot.img"
  fi
fi
unset _fox_device_path _fox_top

# Build identity
export FOX_BUILD_DEVICE="fire"
export FOX_BUILD_TYPE="Unofficial"
export OF_MAINTAINER="~VicTim~"
export BUILD_USERNAME="VicTim"
export BUILD_HOSTNAME="OrangeFox"

# Build environment
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"

# Boot image patching
export OF_USE_MAGISKBOOT=1
export OF_USE_MAGISKBOOT_FOR_ALL_PATCHES=1
export OF_DONT_PATCH_ENCRYPTED_DEVICE=1

# A/B, virtual A/B and dynamic partitions
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_VENDOR_BOOT_RECOVERY=1
export OF_ENABLE_LPTOOLS=1
export OF_IGNORE_LOGICAL_MOUNT_ERRORS=1

# Encryption and data format handling
export OF_KEEP_FORCED_ENCRYPTION=1
export OF_WIPE_METADATA_AFTER_DATAFORMAT=1

# Screen and status bar
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_CLOCK_POS=1
export OF_SCREEN_H=2460
export OF_STATUS_H=120

# Flashlight. The MTK torch node updates through brightness_clone.
export OF_FLASHLIGHT_ENABLE=1
export OF_FL_PATH1="/tmp/fox_flashlight"

# Installer behavior
export OF_NO_TREBLE_COMPATIBILITY_CHECK=1
export OF_DISABLE_MIUI_OTA_BY_DEFAULT=1
export OF_NO_SPLASH_CHANGE=1
export FOX_INSTALLER_DISABLE_AUTOREBOOT=1
export FOX_INSTALLER_VENDOR_BOOT_RAMDISK_INSTALL=0

# Backup defaults
export OF_QUICK_BACKUP_LIST="/boot;/data;/super;"

# Extra tools
export FOX_DELETE_AROMAFM=1
export FOX_USE_BASH_SHELL=1
export FOX_USE_NANO_EDITOR=1
export OF_USE_GREEN_LED=0
