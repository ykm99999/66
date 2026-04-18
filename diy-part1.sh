#!/bin/bash
# [物理审计] 终极方案：十六进制物理注入，彻底封死 Missing Separator 错误

TARGET_MK="target/linux/mediatek/image/filogic.mk"

# 1. 物理重置并写入头部
printf "DTS_DIR := \$(DTS_DIR)/mediatek\n\n" > "$TARGET_MK"

# 2. 注入 Prepare 宏
printf "define Image/Prepare\n\trm -f \$(KDIR)/ubi_mark\n\techo -ne '\\xde\\xad\\xc0\\xde' > \$(KDIR)/ubi_mark\nendef\n\n" >> "$TARGET_MK"

# 3. 注入基础构建宏
printf "define Build/mt7981-bl2\n\tcat \$(STAGING_DIR_IMAGE)/mt7981-\$(1)-bl2.img >> \$@\nendef\n\n" >> "$TARGET_MK"
printf "define Build/mt7981-bl31-uboot\n\tcat \$(STAGING_DIR_IMAGE)/mt7981_\$(1)-u-boot.fip >> \$@\nendef\n\n" >> "$TARGET_MK"

# 4. 核心注入：gen_spi_full_32mb (使用十六进制补丁确保 Tab)
# 注意：每行前面的 \t 是由 printf 解释为 0x09 字节码
/usr/bin/printf "define Build/gen_spi_full_32mb\n\t@echo \"=== 物理审计：正在合成 32MB 救砖镜像 ===\"\n\tdd if=/dev/zero bs=1M count=32 | tr '\\\\000' '\\\\377' > \$@.tmp\n\t[ -f \$(BIN_DIR)/bl2.img ] && dd if=\$(BIN_DIR)/bl2.img of=\$@.tmp conv=notrunc status=none\n\t[ -f \$(BIN_DIR)/fip.bin ] && dd if=\$(BIN_DIR)/fip.bin of=\$@.tmp bs=1M seek=1 conv=notrunc status=none\n\t[ -f \$(BIN_DIR)/factory.bin ] && dd if=\$(BIN_DIR)/factory.bin of=\$@.tmp bs=1M seek=2 conv=notrunc status=none\n\t[ -f \$(KDIR)/fit-mt7981b-sl3000-emmc.itb ] && dd if=\$(KDIR)/fit-mt7981b-sl3000-emmc.itb of=\$@.tmp bs=1M seek=3 conv=notrunc status=none\n\tmv \$@.tmp \$@\nendef\n\n" >> "$TARGET_MK"

# 5. 注入 SL3000 设备定义 (像素级对齐名称与 1024M RAM)
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

# 6. 最后的物理对齐审计：强制转换所有行首空格为 Tab
sed -i 's/^    /\t/g' "$TARGET_MK"
sed -i 's/^  /\t/g' "$TARGET_MK" # 针对 Device 定义内部的空格纠偏
