#!/bin/bash
# =========================================================
# SL-3000 救砖全家桶：零件物理预埋脚本 (完整版)
# =========================================================

# 1. 物理目录初始化：清理并建立预埋区
rm -rf package/boot/arm-trusted-firmware-mediatek/files
rm -rf package/boot/uboot-mediatek/files
mkdir -p package/boot/arm-trusted-firmware-mediatek/files
mkdir -p package/boot/uboot-mediatek/files

# 2. 物理劫持：强制替换 Makefile 为我们的硬化版本
cp -f ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -f ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# 3. 零件预埋：将 888 目录下的救砖零件存入预埋区
# ATF 零件
cp -f ../888/bl2_dev_spi_nor.c package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/bl2.mk package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/platform.mk package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/platform_def.h package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/mt7981-spi2.dts package/boot/arm-trusted-firmware-mediatek/files/

# U-Boot 零件
cp -f ../888/mt7981_sl3000_defconfig package/boot/uboot-mediatek/files/

# 4. 系统配置预设
if [ -f ../888/sl3000.config ]; then
    cp -f ../888/sl3000.config .config
fi

echo "--- [物理溯源]：全链路零件已落位，待命编译 ---"
