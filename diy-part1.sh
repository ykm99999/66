#!/bin/bash
# 物理审计：修复 Missing Separator 错误，强制物理 Tab 注入

OPENWRT_ROOT="openwrt"
TARGET_MK="$OPENWRT_ROOT/target/linux/mediatek/image/filogic.mk"

# 1. 物理清空并重新注入基础定义
# 注意：命令行的开头使用了 \t 占位符，由 printf 解析为物理 Tab
printf "DTS_DIR := \$(DTS_DIR)/mediatek\n\n" > "$TARGET_MK"

printf "define Image/Prepare\n\trm -f \$(KDIR)/ubi_mark\n\techo -ne '\\xde\\xad\\xc0\\xde' > \$(KDIR)/ubi_mark\nendef\n\n" >> "$TARGET_MK"

printf "define Build/mt7981-bl2\n\tcat \$(STAGING_DIR_IMAGE)/mt7981-\$1-bl2.img >> \$@\nendef\n\n" >> "$TARGET_MK"

printf "define Build/mt7981-bl31-uboot\n\tcat \$(STAGING_DIR_IMAGE)/mt7981_\$1-u-boot.fip >> \$@\nendef\n\n" >> "$TARGET_MK"

# 2. 物理注入 SL3000 合成宏 (核心 Tab 修复)
printf "define Build/gen_spi_full_32mb\n" >> "$TARGET_MK"
printf "\t@echo \"=== 物理合成：32MB 救砖镜像 ===\"\n" >> "$TARGET_MK"
printf "\tdd if=/dev/zero bs=1M count=32 | tr '\\000' '\\377' > \$@.tmp\n" >> "$TARGET_MK"
printf "\t[ -f \$(BIN_DIR)/bl2.img ] && dd if=\$(BIN_DIR)/bl2.img of=\$@.tmp conv=notrunc status=none\n" >> "$TARGET_MK"
printf "\t[ -f \$(BIN_DIR)/fip.bin ] && dd if=\$(BIN_DIR)/fip.bin of=\$@.tmp bs=1M seek=1 conv=notrunc status=none\n" >> "$TARGET_MK"
printf "\t[ -f \$(BIN_DIR)/factory.bin ] && dd if=\$(BIN_DIR)/factory.bin of=\$@.tmp bs=1M seek=2 conv=notrunc status=none\n" >> "$TARGET_MK"
printf "\t[ -f \$(KDIR)/fit-mt7981b-sl3000-emmc.itb ] && dd if=\$(KDIR)/fit-mt7981b-sl3000-emmc.itb of=\$@.tmp bs=1M seek=3 conv=notrunc status=none\n" >> "$TARGET_MK"
printf "\tmv \$@.tmp \$@\n" >> "$TARGET_MK"
printf "endef\n\n" >> "$TARGET_MK"

# 3. 物理注入设备定义
printf "define Device/mt7981_sl3000_spi_rescue\n" >> "$TARGET_MK"
printf "  DEVICE_VENDOR := Siluo\n" >> "$TARGET_MK"
printf "  DEVICE_MODEL := SL3000\n" >> "$TARGET_MK"
printf "  DEVICE_VARIANT := SPI Full (1GB DDR4 / 32MB NOR)\n" >> "$TARGET_MK"
printf "  DEVICE_DTS := mt7981b-sl3000-emmc\n" >> "$TARGET_MK"
printf "  SUPPORTED_DEVICES := siluo,sl3000-emmc\n" >> "$TARGET_MK"
printf "  DEVICE_DRAM_SIZE := 1024M\n" >> "$TARGET_MK"
printf "  SOC := mt7981\n" >> "$TARGET_MK"
printf "  KERNEL_LOADADDR := 0x44000000\n" >> "$TARGET_MK"
printf "  KERNEL := kernel-bin | gzip\n" >> "$TARGET_MK"
printf "  IMAGES := spi-full-32mb.bin\n" >> "$TARGET_MK"
printf "  IMAGE/spi-full-32mb.bin := gen_spi_full_32mb\n" >> "$TARGET_MK"
printf "  DEVICE_PACKAGES := uboot-envtools mtd-utils kmod-mtd-rw block-mount kmod-mmc kmod-mmc-mtk kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs ip-full dropbear\n" >> "$TARGET_MK"
printf "endef\n" >> "$TARGET_MK"
printf "TARGET_DEVICES += mt7981_sl3000_spi_rescue\n" >> "$TARGET_MK"

echo "✅ 修复完成：使用物理 \t (Tab) 重新生成了 filogic.mk"
