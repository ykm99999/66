#!/bin/bash

# --- 1. 物理粉碎 ---
# 在源码目录(openwrt)内执行
cd openwrt
rm -rf tmp .config

# --- 2. 物理校准 ATF Makefile ---
ATF_PATH="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_PATH" ]; then
    # 物理修正：Include 改小写，行首空格转 Tab
    sed -i 's/Include/include/g' "$ATF_PATH"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_PATH"
    echo "ATF Makefile 物理对齐完成。"
fi

# --- 3. 物理注入 U-Boot 定义 ---
UBOOT_PATH="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_PATH" ]; then
    if ! grep -q "mt7981_sl3000_emmc" "$UBOOT_PATH"; then
        sed -i '/define U-Boot\/mt7981-sd-emmc/i \
define U-Boot/mt7981_sl3000_emmc\n  NAME:=SL-3000 (eMMC)\n  BUILD_SUBTARGET:=filogic\n  BUILD_DEVICES:=mediatek_mt7981\n  DEPENDS:=+arm-trusted-firmware-mediatek-mt7981-sl3000-emmc\nendef\n' "$UBOOT_PATH"
        sed -i 's/UBOOT_TARGETS := \\/UBOOT_TARGETS := mt7981_sl3000_emmc \\/' "$UBOOT_PATH"
    fi
fi
