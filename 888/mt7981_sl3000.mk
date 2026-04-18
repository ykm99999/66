# 执行此命令以物理修复并生成完整的 888/mt7981_sl3000.mk
printf '%s\n' \
'# SPDX-License-Identifier: GPL-2.0-or-later' \
'# 物理修复版：全自包含模式，禁用外部 include' \
'' \
'define Device/mt7981_sl3000_spi_rescue' \
'  DEVICE_VENDOR := Siluo' \
'  DEVICE_MODEL := SL3000' \
'  DEVICE_VARIANT := SPI Full (1GB DDR4 / 32MB NOR)' \
'  DEVICE_DTS := mt7981b-sl-3000-emmc' \
'  SUPPORTED_DEVICES := siluo,sl3000-spi-rescue' \
'  DEVICE_DRAM_SIZE := 1024M' \
'  SOC := mt7981' \
'  UBOOTENV_IN_FLASH := 1' \
'  KERNEL_IN_UBI := 0' \
'  KERNEL_LOADADDR := 0x44000000' \
'  KERNEL := kernel-bin | gzip' \
'  KERNEL_INITRAMFS := kernel-bin | gzip' \
'  IMAGES := spi-full-32mb.bin' \
'  IMAGE/spi-full-32mb.bin := gen_spi_full_32mb' \
'  DEVICE_PACKAGES := uboot-envtools mtd-utils kmod-mtd-rw block-mount kmod-mmc kmod-mmc-mtk kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs ip-full dropbear' \
'endef' \
'' \
'define Build/gen_spi_full_32mb' \
'	@echo "=== 物理审计：正在合成 32MB 救砖镜像 ==="' \
'	dd if=/dev/zero bs=1M count=32 | tr '"'"'\000'"'"' '"'"'\377'"'"' > $@.tmp' \
'	# 偏移对齐校验：0M->BL2, 1M->FIP, 2M->Factory, 3M->Kernel' \
'	[ -f $(BIN_DIR)/bl2.img ] && dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none' \
'	[ -f $(BIN_DIR)/fip.bin ] && dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=1M seek=1 conv=notrunc status=none' \
'	[ -f $(BIN_DIR)/factory.bin ] && dd if=$(BIN_DIR)/factory.bin of=$@.tmp bs=1M seek=2 conv=notrunc status=none' \
'	# 动态适配内核 FIT 路径' \
'	[ -f $(KDIR)/fit-mt7981b-sl-3000-emmc.itb ] && dd if=$(KDIR)/fit-mt7981b-sl-3000-emmc.itb of=$@.tmp bs=1M seek=3 conv=notrunc status=none' \
'	mv $@.tmp $@' \
'	@echo "✅ 32MB 救砖镜像合成成功：$@"' \
'endef' \
'' \
'TARGET_DEVICES += mt7981_sl3000_spi_rescue' > 888/mt7981_sl3000.mk
