# SPDX-License-Identifier: GPL-2.0-or-later
# 全链路溯源诊断：锁定 SL3000 基因对齐 (1024M RAM / 32MB SPI)

DTS_DIR := $(DTS_DIR)/mediatek

define Image/Prepare
	rm -f $(KDIR)/ubi_mark
	echo -ne '\xde\xad\xc0\xde' > $(KDIR)/ubi_mark
endef

# --- 物理基础构建宏 ---
define Build/mt7981-bl2
	cat $(STAGING_DIR_IMAGE)/mt7981-$(1)-bl2.img >> $@
endef

define Build/mt7981-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7981_$(1)-u-boot.fip >> $@
endef

# --- SL3000 专用物理合成宏 (锁定 32MB 救砖镜像) ---
define Build/gen_spi_full_32mb
	@echo "=== 物理审计：正在合成 32MB 救砖镜像 ==="
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp
	# 物理偏移锁定：0M-BL2, 1M-FIP, 2M-Factory, 3M-Kernel
	[ -f $(BIN_DIR)/bl2.img ] && dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none
	[ -f $(BIN_DIR)/fip.bin ] && dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=1M seek=1 conv=notrunc status=none
	[ -f $(BIN_DIR)/factory.bin ] && dd if=$(BIN_DIR)/factory.bin of=$@.tmp bs=1M seek=2 conv=notrunc status=none
	# 基因索引：必须引用 fit-mt7981b-sl3000-emmc.itb
	[ -f $(KDIR)/fit-mt7981b-sl3000-emmc.itb ] && dd if=$(KDIR)/fit-mt7981b-sl3000-emmc.itb of=$@.tmp bs=1M seek=3 conv=notrunc status=none
	mv $@.tmp $@
	@echo "✅ 32MB 救砖镜像合成对齐成功"
endef

# --- SL3000 设备定义 (1024M RAM 像素级对齐) ---
define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Full (1GB DDR4 / 32MB NOR)
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-emmc
  DEVICE_DRAM_SIZE := 1024M
  SOC := mt7981
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  IMAGES := spi-full-32mb.bin
  IMAGE/spi-full-32mb.bin := gen_spi_full_32mb
  DEVICE_PACKAGES := uboot-envtools mtd-utils kmod-mtd-rw block-mount kmod-mmc kmod-mmc-mtk kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs ip-full dropbear
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
