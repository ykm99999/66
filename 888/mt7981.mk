define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
	luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  
  IMAGES := sysupgrade.bin nor-programmer-dump.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  
  # 物理刻度精准对齐：
  # 1. BL2 放在 0 处
  # 2. FIP 强制跳过前面的 2MB (包含 env 和 factory) 放在 2M 处
  IMAGE/nor-programmer-dump.bin := \
	append-image-stage mt7981-nor-ddr4-bl2.img | pad-to 2048k | \
	append-image-stage mt7981_sl3000_nor-fip.bin | pad-to 4096k | \
	append-kernel | pad-to 12M | \
	append-rootfs | pad-to 32M | check-size 32M
endef
TARGET_DEVICES += sl_3000-emmc
