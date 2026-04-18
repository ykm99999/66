# SPDX-License-Identifier: GPL-2.0-or-later

DTS_DIR := $(DTS_DIR)/mediatek

define Image/Prepare
	# For UBI we want only one extra block
	rm -f $(KDIR)/ubi_mark
	echo -ne '\xde\xad\xc0\xde' > $(KDIR)/ubi_mark
endef

# --- 物理基础构建宏 ---
define Build/mt7981-bl2
	cat $(STAGING_DIR_IMAGE)/mt7981-$1-bl2.img >> $@
endef

define Build/mt7981-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7981_$1-u-boot.fip >> $@
endef

define Build/mt798x-gpt
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
		$(if $(findstring sdmmc,$1), -H -t 0x83 -N bl2 -r -p 4079k@17k ) \
		-t 0x83 -N ubootenv -r -p 512k@4M \
		-t 0x83 -N factory -r -p 2M@4608k \
		-t 0xef -N fip -r -p 4M@6656k \
		-N recovery -r -p 32M@12M \
		$(if $(findstring sdmmc,$1), -N install -r -p 20M@44M -t 0x2e -N production -p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M ) \
		$(if $(findstring emmc,$1), -t 0x2e -N production -p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M )
	cat $@.tmp >> $@
	rm $@.tmp
endef

# --- SL3000 专用物理合成宏 ---
define Build/gen_spi_full_32mb
	@echo "=== 物理审计：正在合成 32MB 救砖镜像 ==="
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp
	# 偏移对齐：0M->BL2, 1M->FIP, 2M->Factory, 3M->Kernel (适配 DTS partition@300000)
	[ -f $(BIN_DIR)/bl2.img ] && dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none
	[ -f $(BIN_DIR)/fip.bin ] && dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=1M seek=1 conv=notrunc status=none
	[ -f $(BIN_DIR)/factory.bin ] && dd if=$(BIN_DIR)/factory.bin of=$@.tmp bs=1M seek=2 conv=notrunc status=none
	[ -f $(KDIR)/fit-mt7981b-sl3000-emmc.itb ] && dd if=$(KDIR)/fit-mt7981b-sl3000-emmc.itb of=$@.tmp bs=1M seek=3 conv=notrunc status=none
	mv $@.tmp $@
	@echo "✅ 32MB 救砖镜像名称对齐合成成功"
endef

# --- SL3000 设备定义 (1024M RAM 对齐版) ---
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
