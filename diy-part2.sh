#!/bin/bash
# 物理溯源硬化：零件预埋脚本

# 1. 清理并创建物理预埋目录
rm -rf package/boot/arm-trusted-firmware-mediatek/files
rm -rf package/boot/uboot-mediatek/files
mkdir -p package/boot/arm-trusted-firmware-mediatek/files
mkdir -p package/boot/uboot-mediatek/files

# 2. 劫持 Makefile (核心总闸)
cp -f ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -f ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -f ../888/sl3000.config .config

# 3. 物理预埋 ATF 零件
cp -f ../888/bl2_dev_spi_nor.c package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/bl2.mk package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/platform.mk package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/platform_def.h package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/mt7981-spi2.dts package/boot/arm-trusted-firmware-mediatek/files/

# 4. 物理预埋 U-Boot 零件
cp -f ../888/mt7981_sl3000_defconfig package/boot/uboot-mediatek/files/

echo "物理零件已落位，全链路闭环就绪。"
