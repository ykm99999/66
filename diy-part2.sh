#!/bin/bash
# =========================================================
# SL-3000 救砖全家桶：零件物理预埋与名称同步脚本 (修复版)
# =========================================================

# 1. 物理目录初始化：清理并建立预埋区
rm -rf package/boot/arm-trusted-firmware-mediatek/files
rm -rf package/boot/uboot-mediatek/files
mkdir -p package/boot/arm-trusted-firmware-mediatek/files
mkdir -p package/boot/uboot-mediatek/files

# 2. 物理劫持：强制替换 Makefile 为我们的救砖硬化版本
cp -f ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -f ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# 3. ATF 零件预埋 (实现 1MB 偏移的核心代码)
cp -f ../888/bl2_dev_spi_nor.c package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/bl2.mk package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/platform.mk package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/platform_def.h package/boot/arm-trusted-firmware-mediatek/files/
cp -f ../888/mt7981-spi2.dts package/boot/arm-trusted-firmware-mediatek/files/

# 4. U-Boot 零件预埋 (含专属 eMMC DTS)
cp -f ../888/mt7981_sl3000_defconfig package/boot/uboot-mediatek/files/
# 必须搬运此文件，uboot-Makefile 才能进行身份重定向
cp -f ../888/mt7981-sl-3000-emmc.dts package/boot/uboot-mediatek/files/

# 5. 内核 (Kernel) 镜像合成物理劫持
# 物理欺骗：在内核源码目录注入同名 DTS，确保 .mk 合成镜像时不报 Error 1
mkdir -p target/linux/mediatek/dts/
cp -f ../888/mt7981-sl-3000-emmc.dts target/linux/mediatek/dts/mt7981-sl3000.dts

# 6. 系统配置预设
if [ -f ../888/sl3000.config ]; then
    cp -f ../888/sl3000.config .config
fi

echo "--- [物理溯源]：全链路零件（含 eMMC DTS）已落位 ---"
