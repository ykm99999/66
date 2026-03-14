#
# Copyright (C) 2024-2026 ykm888 (Physical Aligned for 24.10)
#

# --- 1. 定义 GPT eMMC 分区布局 (物理对齐 128G 硬件) ---
define Build/mt798x-gpt-emmc-production
	ptgen -g -o $@ -a 1 \
		-t 0x83 -N ubootenv -r -p 512k@4M \
		-t 0x83 -N factory -r -p 2M@5M \
		-t 0x83 -N kernel -r -p 64M@64M \
		-t 0x83 -N production -p 1024M@128M
endef

# --- 2. 定义 32MB NOR 救砖全家桶 (物理真名像素级对齐) ---
define Build/sl3000-nor-bundle
	rm -f $@.nor
	touch $@.nor
	truncate -s 32M $@.nor
	
	# [物理零件 A]: 搜寻 BL2
	# 物理修正：24.10 下 TFA 变体文件名通常包含 PKG_NAME
	BL2_FILE=""; \
	for f in "$(STAGING_DIR_IMAGE)/bl2.img" \
	         "$(STAGING_DIR_IMAGE)/arm-trusted-firmware-mediatek-$(TFA_PART)-bl2.bin" \
	         "$(STAGING_DIR_IMAGE)/trusted-firmware-a-$(TFA_PART)-bl2.bin"; do \
		[ -f "$$f" ] && BL2_FILE="$$f" && break; \
	done; \
	if [ -n "$$BL2_FILE" ]; then \
		echo "Physical Found BL2: $$BL2_FILE"; \
		dd if=$$BL2_FILE of=$@.nor bs=1k conv=notrunc; \
	else \
		echo "!!! ERROR: bl2.img 未找到 !!!"; exit 1; \
	fi; \
	
	# [物理零件 B]: 搜寻 U-Boot 并注入 1MB 偏移
	UBOOT_FILE=""; \
	for f in "$(STAGING_DIR_IMAGE)/uboot-mediatek-$(TFA_PART)-u-boot.bin" \
	         "$(STAGING_DIR_IMAGE)/u-boot.bin"; do \
		[ -f "$$f" ] && UBOOT_FILE="$$f" && break; \
	done; \
	if [ -n "$$UBOOT_FILE" ]; then \
		echo "Physical Found U-Boot: $$UBOOT_FILE"; \
		dd if=$$UBOOT_FILE of=$@.nor bs=1k seek=1024 conv=notrunc; \
	else \
		echo "!!! ERROR: u-boot.bin 未找到 !!!"; exit 1; \
	fi; \
	
	cp $@.nor $@
	rm -f $@.nor
endef

# --- 3. 设备定义 ---
define Device/sl_3000-nor-emmc
  DEVICE_VENDOR := ykm888
  DEVICE_MODEL := SL-3000
  DEVICE_VARIANT := 512M-RAM-Stable
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ykm888,sl-3000
  TFA_PART := mt7981-nor-ddr4
  
  DEVICE_PACKAGES := kmod-mmc-mtk kmod-mtk-sd f2fs-tools kmod-fs-f2fs \
                     kmod-fs-ext4 parted resize2fs
  
  IMAGES := nor-programmer-dump.bin emmc-sysupgrade.bin
  IMAGE/nor-programmer-dump.bin := sl3000-nor-bundle
  IMAGE/emmc-sysupgrade.bin := mt798x-gpt-emmc-production | pad-to 64M | append-kernel | pad-to 128M | append-rootfs | append-metadata
endef
TARGET_DEVICES += sl_3000-nor-emmc
