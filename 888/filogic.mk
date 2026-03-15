# 官方路径: target/linux/mediatek/image/filogic.mk

define Build/mt7981-bl2
	cat $(STAGING_DIR_IMAGE)/mt7981-$1-bl2.img >> $@
endef

define Build/mt7981-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7981_$1-u-boot.fip >> $@
endef

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (DDR4-Rescue)
  DEVICE_DTS := mt7981b-sl-3000-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware automount coremark blkid blockdev fdisk f2fsck mkf2fs kmod-mmc
  
  # 物理救砖拼装：BL2(1MB) + U-Boot(偏移) + 全量填充
  IMAGES += nor-programmer-dump.bin
  IMAGE/nor-programmer-dump.bin := \
	mt7981-bl2 nor-ddr4 | pad-to 1024k | \
	mt7981-bl31-uboot sl3000_nor | pad-to 32768k
  
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
