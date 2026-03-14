#!/bin/bash
# SL-3000 Physical Hardening Script
# 准则：环境确定性 - 强制物理路径对齐

set -e

PATCH_SRC="./888"
# 自动定位 ATF 和 U-Boot 的构建目录
ATF_DIR=$(find ./openwrt/build_dir -name "arm-trusted-firmware-mediatek-*" -type d | head -n 1)
UBOOT_DIR=$(find ./openwrt/build_dir -name "uboot-mediatek-*" -type d | head -n 1)

echo "--- 开始物理硬化注入 ---"

# 1. ATF 核心硬化 (1MB 偏移驱动与控制)
if [ -d "$ATF_DIR" ]; then
    echo "注入 ATF 补丁到: $ATF_DIR"
    cp -v $PATCH_SRC/bl2_dev_spi_nor.c $ATF_DIR/plat/mediatek/mt7981/bl2/
    cp -v $PATCH_SRC/bl2.mk $ATF_DIR/plat/mediatek/mt7981/bl2/
    cp -v $PATCH_SRC/platform.mk $ATF_DIR/plat/mediatek/mt7981/
    cp -v $PATCH_SRC/platform_def.h $ATF_DIR/plat/mediatek/mt7981/include/
    # 物理地图 (DTS) 覆盖
    find $ATF_DIR -name "mt7981-spi2.dts" -exec cp -v $PATCH_SRC/mt7981-spi2.dts {} \;
else
    echo "错误：未发现 ATF 构建目录，请检查编译状态。" && exit 1
fi

# 2. U-Boot 核心硬化 (DDR4 与 1MB 救砖配置)
if [ -d "$UBOOT_DIR" ]; then
    echo "注入 U-Boot 配置到: $UBOOT_DIR"
    cp -v $PATCH_SRC/sl3000.config $UBOOT_DIR/configs/mt7981_sl3000_defconfig
else
    echo "警告：未发现 U-Boot 构建目录，跳过 U-Boot 注入。"
fi

# 3. 构建框架硬化 (OpenWrt Makefile)
echo "更新编译框架 Makefile..."
cp -v $PATCH_SRC/atf-Makefile ./openwrt/package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v $PATCH_SRC/uboot-Makefile ./openwrt/package/boot/uboot-mediatek/Makefile
cp -v $PATCH_SRC/filogic.mk ./openwrt/target/linux/mediatek/image/filogic.mk

echo "--- 物理执行：补丁链路已闭环 ---"
