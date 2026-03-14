#
# Copyright (C) 2024-2026 ykm888 (Physical Aligned for 24.10)
#

# --- 1. 定义 GPT eMMC 分区布局 (128G 物理硬化) ---
define Build/mt798x-gpt-emmc-production
	ptgen -g -o $@ -a 1 \
		-t 0x83 -N ubootenv -r -p 512k@4M \
		-t 0x83 -N factory -r -p 2M@5M \
		-t 0x83 -N kernel -r -p 64M@64M \
		-t 0x83 -N production -p 1024M@128M
endef

# --- 2. 定义 32MB NOR 救砖全家桶 (全路径模糊扫描缝合) ---
define Build/sl3000-nor-bundle
	rm -f $@.nor
	touch $@.nor
	truncate -s 32M $@.nor
	
	# [物理零件 A]: 智能搜寻 BL2
	# 使用 wildcard 兼容所有可能的 PKG_NAME 前缀
	$(eval BL2_PATH=$(wildcard $(STAGING_DIR_IMAGE)/*bl2.bin $(STAGING_DIR_IMAGE)/bl2.img))
	@if [ -n "$(BL2_PATH)" ]; then \
		echo "Physical Found BL2: $(BL2_PATH)"; \
		dd if=$(firstword $(BL2_PATH)) of=$@.nor bs=1k conv=notrunc; \
	else \
		echo "!!! ERROR: BL2 零件丢失，请检查 atf-Makefile !!!"; exit 1; \
	fi
	
	# [物理零件 B]: 智能搜寻 U-Boot 并执行 1MB 偏移注入
	# 物理逻辑：dd seek=1024 对应你的 bl2_dev_spi_nor.c 加固补丁
	$(eval UBOOT_PATH=$(wildcard $(STAGING_DIR_IMAGE)/*u-boot.bin $(STAGING_DIR_IMAGE)/u-boot.bin))
	@if [ -n "$(UBOOT_PATH)" ]; then \
		echo "Physical Found U-Boot: $(UBOOT_PATH)"; \
		dd if=$(firstword $(UBOOT_PATH)) of=$@.nor bs=1k seek=1024 conv=notrunc; \
	else \
		echo "!!! ERROR: U-Boot 零件丢失，请检查 uboot-Makefile !!!"; exit 1; \
	fi
	
	cp $@.nor $@
	rm -f $@.nor
endef

# --- 3. 设备定义 ---
define Device/sl_3000
  DEVICE_VENDOR := ykm888
  DEVICE_MODEL := SL-3000
  DEVICE_VARIANT := 512M-RAM-Stable
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ykm888,sl-3000
  
  # 驱动对齐：6.6 内核标准驱动包
  DEVICE_PACKAGES := kmod-mmc kmod-mtk-sd f2fs-tools kmod-fs-f2fs \
                     kmod-fs-ext4 parted fdisk resize2fs
  
  IMAGES := nor-programmer-dump.bin emmc-sysupgrade.bin
  IMAGE/nor-programmer-dump.bin := sl3000-nor-bundle
  IMAGE/emmc-sysupgrade.bin := mt798x-gpt-emmc-production | pad-to 64M | append-kernel | pad-to 128M | append-rootfs | append-metadata
endef

TARGET_DEVICES += sl_3000
