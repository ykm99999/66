#!/bin/bash
# 物理审计：SL3000 全链路基因锁定脚本 (禁用 EOF)

# 1. 物理环境准备
USER_DTS="main-repo/888/mt7981b-sl3000-emmc.dts"
OPENWRT_ROOT="openwrt"

# 2. DTS 像素级多路径注入 (放宽路径策略)
if [ -f "$USER_DTS" ]; then
    echo "=== [物理审计] 正在注入 DTS 到所有索引路径 ==="
    
    # 路径 A: 架构通用目录 (Image Builder 预检点)
    mkdir -p "$OPENWRT_ROOT/target/linux/mediatek/dts"
    cp -f "$USER_DTS" "$OPENWRT_ROOT/target/linux/mediatek/dts/mt7981b-sl3000-emmc.dts"
    
    # 路径 B: 6.6 内核特定目录 (内核编译点)
    KERNEL_DTS_DIR="$OPENWRT_ROOT/target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
    mkdir -p "$KERNEL_DTS_DIR"
    cp -f "$USER_DTS" "$KERNEL_DTS_DIR/mt7981b-sl3000-emmc.dts"
    
    echo "✅ DTS 物理链路已闭合"
else
    echo "❌ 错误：未在 main-repo/888/ 下找到 DTS，请检查仓库！"
    exit 1
fi

# 3. 物理覆盖 filogic.mk (仅保留 SL3000 相关逻辑)
# 这一步直接重写该文件，删除所有无关设备，防止编译冲突
printf '%s\n' \
'# SPDX-License-Identifier: GPL-2.0-or-later' \
'DTS_DIR := $(DTS_DIR)/mediatek' \
'define Image/Prepare' \
'	rm -f $(KDIR)/ubi_mark' \
'	echo -ne '"'"'\xde\xad\xc0\xde'"'"' > $(KDIR)/ubi_mark' \
'endef' \
'define Build/mt7981-bl2' \
'	cat $(STAGING_DIR_IMAGE)/mt7981-$1-bl2.img >> $@' \
'endef' \
'define Build/mt7981-bl31-uboot' \
'	cat $(STAGING_DIR_IMAGE)/mt7981_$1-u-boot.fip >> $@' \
'endef' \
'define Build/gen_spi_full_32mb' \
'	@echo "=== 物理合成：32MB 救砖镜像 ==="' \
'	dd if=/dev/zero bs=1M count=32 | tr '"'"'\000'"'"' '"'"'\377'"'"' > $@.tmp' \
'	[ -f $(BIN_DIR)/bl2.img ] && dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none' \
'	[ -f $(BIN_DIR)/fip.bin ] && dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=1M seek=1 conv=notrunc status=none' \
'	[ -f $(BIN_DIR)/factory.bin ] && dd if=$(BIN_DIR)/factory.bin of=$@.tmp bs=1M seek=2 conv=notrunc status=none' \
'	[ -f $(KDIR)/fit-mt7981b-sl3000-emmc.itb ] && dd if=$(KDIR)/fit-mt7981b-sl3000-emmc.itb of=$@.tmp bs=1M seek=3 conv=notrunc status=none' \
'	mv $@.tmp $@' \
'endef' \
'define Device/mt7981_sl3000_spi_rescue' \
'  DEVICE_VENDOR := Siluo' \
'  DEVICE_MODEL := SL3000' \
'  DEVICE_VARIANT := SPI Full (1GB DDR4 / 32MB NOR)' \
'  DEVICE_DTS := mt7981b-sl3000-emmc' \
'  SUPPORTED_DEVICES := siluo,sl3000-emmc' \
'  DEVICE_DRAM_SIZE := 1024M' \
'  SOC := mt7981' \
'  KERNEL_LOADADDR := 0x44000000' \
'  KERNEL := kernel-bin | gzip' \
'  IMAGES := spi-full-32mb.bin' \
'  IMAGE/spi-full-32mb.bin := gen_spi_full_32mb' \
'  DEVICE_PACKAGES := uboot-envtools mtd-utils kmod-mtd-rw block-mount kmod-mmc kmod-mmc-mtk kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs ip-full dropbear' \
'endef' \
'TARGET_DEVICES += mt7981_sl3000_spi_rescue' > "$OPENWRT_ROOT/target/linux/mediatek/image/filogic.mk"

# 4. 物理致盲：封印 Mconf 交互弹窗
printf '%s\n' '#!/bin/sh' 'echo "[物理审计] 锁定静默模式"' 'exit 1' > "$OPENWRT_ROOT/scripts/config/mconf-cfg.sh"
chmod +x "$OPENWRT_ROOT/scripts/config/mconf-cfg.sh"

echo "✅ SL3000 编译基因已物理注入并对齐"
