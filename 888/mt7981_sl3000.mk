define Device/mt7981_sl3000_emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := eMMC
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := sl,sl3000

  KERNEL_LOADADDR := 0x48000000

  # eMMC 救砖完整包（适配你机器）
  DEVICE_PACKAGES := \
	luci luci-base luci-mod-system luci-theme-bootstrap \
	block-mount e2fsprogs f2fs-tools \
	kmod-fs-ext4 kmod-fs-f2fs \
	kmod-mtd kmod-mtd-rw \
	kmod-sdhci-mtk \
	dropbear \
	lsblk blkid mount-utils \
	mtd-utils uboot-envtools

  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += mt7981_sl3000_emmc
