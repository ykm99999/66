#
# Copyright (C) 2024-2026 ykm888 (Physical Aligned for 24.10)
# 司络 SL-3000 硬件加固版：32MB NOR 救砖 + 128GB eMMC 引导
#

# --- 1. 定义 GPT eMMC 分区布局 (物理对齐 128G 硬件) ---
# 严格锁定内核 64M 起点，生产分区 (production) 锁定在 128M 偏移处
define Build/mt798x-gpt-emmc-production
	ptgen -g -o $@ -a 1 \
		-t 0x83 -N ubootenv -r -p 512k@4M \
		-t 0x83 -N factory -r -p 2M@5M \
		-t 0x83 -N kernel -r -p 64M@64M \
		-t 0x83 -N production -p 1024M@128M
endef

# --- 2. 定义 32MB NOR 救砖全家桶 (物理零件精准缝合) ---
define Build/sl3000-nor-bundle
	rm -f $@.nor
	touch $@.nor
	# 物理硬化：生成标准 32MB (256Mbit) 编程器固件镜像
	truncate -s 32M $@.nor
	
	# [物理零件 A]: 搜寻 BL2 (由 arm-trusted-firmware-mediatek 生成)
	# 24.10 物理路径溯源：$(STAGING_DIR_IMAGE)/trusted-firmware-a-$(TFA_PART)-bl2.bin
	BL2_FILE=""; \
	for f in "$(STAGING_DIR_IMAGE)/trusted-firmware-a-$(TFA_PART)-bl2.bin" \
	         "$(STAGING_DIR_IMAGE)/bl2-$(TFA_PART).img" \
	         "$(STAGING_DIR_IMAGE)/bl2.img"; do \
		[ -f "$$f" ] && BL2_FILE="$$f" && break; \
	done; \
	if [ -n "$$BL2_FILE" ]; then \
		echo "Physical Found BL2: $$BL2_FILE"; \
		dd if=$$BL2_FILE of=$@.nor bs=1k conv=notrunc; \
	else \
		echo "!!! ERROR: BL2 零件缺失，请检查 atf-Makefile 是否编译成功 !!!"; exit 1; \
	fi; \
	
	# [物理零件 B]: 搜寻 U-Boot 并执行 1MB 物理偏移注入
	# 物理逻辑：dd seek=1024 (1024 * 1KB = 1MB) 必须与 bl2_dev_spi_nor.c 严格对齐
	UBOOT_FILE=""; \
	for f in "$(STAGING_DIR_IMAGE)/uboot-mediatek-$(UBOOT_PART)-u-boot.bin" \
	         "$(STAGING_DIR_IMAGE)/$(UBOOT_PART)-u-boot.bin" \
	         "$(STAGING_DIR_IMAGE)/u-boot.bin"; do \
		[ -f "$$f" ] && UBOOT_FILE="$$f" && break; \
	done; \
	if [ -n "$$UBOOT_FILE" ]; then \
		echo "Physical Found U-Boot: $$UBOOT_FILE"; \
		dd if=$$UBOOT_FILE of=$@.nor bs=1k seek=1024 conv=notrunc; \
	else \
		echo "!!! ERROR: U-Boot 零件缺失，请检查 uboot-Makefile 是否编译成功 !!!"; exit 1; \
	fi; \
	
	cp $@.nor $@
	rm -f $@.nor
endef

# --- 3. 设备定义 (物理坐标中心) ---
define Device/sl_3000
  DEVICE_VENDOR := ykm888
  DEVICE_MODEL := SL-3000
  DEVICE_VARIANT := 512M-RAM-Stable
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ykm888,sl-3000
  
  # 物理锚点：必须与修复后的 Makefile 里的 TFA_TARGETS/UBOOT_TARGETS 像素级对应
  TFA_PART := mt7981-sl3000-nor
  UBOOT_PART := mt7981_sl3000_nor
  
  # 24.10 内核驱动包名对齐
  DEVICE_PACKAGES := kmod-mmc kmod-mtk-sd f2fs-tools kmod-fs-f2fs \
                     kmod-fs-ext4 parted fdisk resize2fs
  
  IMAGES := nor-programmer-dump.bin emmc-sysupgrade.bin
  
  # 生成 32MB 编程器固件
  IMAGE/nor-programmer-dump.bin := sl3000-nor-bundle
  
  # 生成 eMMC 刷机包 (GPT 布局)
  IMAGE/emmc-sysupgrade.bin := mt798x-gpt-emmc-production | pad-to 64M | append-kernel | pad-to 128M | append-rootfs | append-metadata
endef

# 物理挂载：将设备添加到编译队列
TARGET_DEVICES += sl_3000
