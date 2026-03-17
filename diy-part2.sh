#!/bin/bash

# --- 1. 物理粉碎 (断根) ---
# 强制删除所有可能导致架构识别错误的缓存
rm -f .config .config.old
rm -rf tmp/

# --- 2. 物理校准 ATF Makefile ---
# 修复 "recipe commences before first target"
ATF_PATH="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_PATH" ]; then
    # 物理缩进校准：将所有行首空格转为硬 Tab
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_PATH"
    # 关键字校准：确保 include 小写
    sed -i 's/Include/include/g' "$ATF_PATH"
fi

# --- 3. 物理注入 U-Boot 定义 ---
# 确保包名与 sl3000.config 物理握手
UBOOT_PATH="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_PATH" ]; then
    if ! grep -q "mt7981_sl3000_emmc" "$UBOOT_PATH"; then
        sed -i '/define U-Boot\/mt7981-sd-emmc/i \
define U-Boot/mt7981_sl3000_emmc\n  NAME:=SL-3000 (eMMC)\n  BUILD_SUBTARGET:=filogic\n  BUILD_DEVICES:=mediatek_mt7981\n  DEPENDS:=+arm-trusted-firmware-mediatek-mt7981-sl3000-emmc\nendef\n' "$UBOOT_PATH"
        
        # 物理追加到目标列表的第一位
        sed -i 's/UBOOT_TARGETS := \\/UBOOT_TARGETS := mt7981_sl3000_emmc \\/' "$UBOOT_PATH"
    fi
fi

echo "DIY-P2: 物理对齐完成。"
