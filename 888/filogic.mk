#
# Copyright (C) 2024-2026 ykm888 (Physical Aligned for SL-3000)
#

# --- 1. 定义 GPT eMMC 分区布局 (物理分区锁死) ---
define Build/mt798x-gpt-emmc-production
	ptgen -g -o $@ -a 1 \
		-t 0x83 -N ubootenv -r -p 512k@4M \
		-t 0x83 -N factory -r -p 2M@5M \
		-t 0x83 -N kernel -r -p 64M@64M \
		-t 0x83 -N production -p 1024M@128M
endef

# --- 2. 定义 32MB NOR 救砖包合成逻辑 (1MB 物理偏移注入) ---
define Build/sl3000-nor-bundle
	rm -f $@.nor
	touch $@.nor
	# 建立 32MB 物理真空容器
	truncate -s 32M $@.nor
	
	# [物理零件 A]: 智能搜寻 BL2 (ATF)
	$(eval BL2_PATH=$(wildcard $(STAGING_DIR_IMAGE)/*bl2.bin $(STAGING_DIR_IMAGE)/bl2.img))
	@if [ -n "$(BL2_PATH)" ]; then \
		echo "--- [物理注入] BL2: $(firstword $(BL2_PATH)) ---"; \
		dd if=$(firstword $(BL2_PATH)) of=$@.nor bs=1k conv=notrunc; \
	else \
		echo "!!! ERROR: BL2 丢失，请检查 atf-Makefile !!!"; exit 1; \
	fi
	
	# [物理零件 B]: 智能搜寻 U-Boot (FIP) 注入 1MB 偏移处
	# 物理逻辑：seek=1024 (1MB) 确保 BL2 引导成功后能直接物理命中 FIP
	$(eval UBOOT_PATH=$(wildcard $(STAGING_DIR_IMAGE)/*u-boot.bin $(STAGING_DIR_IMAGE)/u-boot.bin))
	@if [ -n "$(UBOOT_PATH)" ]; then \
		echo "--- [物理注入] U-Boot (Offset 1M): $(firstword $(UBOOT_PATH)) ---"; \
		dd if=$(firstword $(UBOOT_PATH)) of=$@.nor bs=1k seek=1024 conv=notrunc; \
	else \
		echo "!!! ERROR: U-Boot 丢失，请检查 uboot-Makefile !!!"; exit 1; \
	fi
	
	cp $@.nor $@
	rm -f $@.nor
endef

# --- 3. SL-3000 设备定义 ---
define Device/sl_3000
  DEVICE_VENDOR := ykm888
  DEVICE_MODEL := SL-3000
  DEVICE_VARIANT := 512M-RAM-eMMC-Stable
  
  # 【物理同步】：像素级对齐你 888 目录下的 DTS 文件名
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  
  # 内核引导物理参数 (MT7981 标定)
  KERNEL_LOADADDR := 0x44000000
  KERNEL_ENTRY := 0x44000000
  KERNEL_NAME := Image
  KERNEL_IN_UBI := 
  
  # 继承 Filogic 系列基础定义
  $(Device/mediatek_mt7981)
  
  SUPPORTED_DEVICES := ykm888,sl-3000 mediatek,mt7981-sl-3000-emmc
  
  # 驱动全家桶：eMMC 控制器 + 常用磁盘工具
  DEVICE_PACKAGES := kmod-mmc kmod-mtk-sd f2fs-tools kmod-fs-f2fs \
                     kmod-fs-ext4 parted fdisk resize2fs block-mount \
                     kmod-usb3 kmod-usb-dwc3-mtk
  
  # 输出镜像清单
  IMAGES := nor-programmer-dump.bin emmc-sysupgrade.bin
  
  # 1. 救砖专用：32MB 编程器固件 (包含 BL2+FIP)
  IMAGE/nor-programmer-dump.bin := sl3000-nor-bundle
  
  # 2. 系统升级：包含 GPT 分区表的 eMMC 专用全量包
  IMAGE/emmc-sysupgrade.bin := mt798x-gpt-emmc-production | pad-to 64M | append-kernel | pad-to 128M | append-rootfs | append-metadata
endef

TARGET_DEVICES += sl_3000
