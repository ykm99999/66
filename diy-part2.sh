#!/bin/bash
# =========================================================
# 司络 SL-3000 (MT7981B) 物理加固脚本 - 像素级修正版
# =========================================================

echo "Starting Physical Injection for SL-3000..."

# --- 1. 物理清场与重建 ---
# 确保目标容器物理存在
rm -rf package/boot/arm-trusted-firmware-mediatek
rm -rf package/boot/uboot-mediatek
mkdir -p package/boot/arm-trusted-firmware-mediatek
mkdir -p package/boot/uboot-mediatek

# --- 2. 物理零件精准注入 ---
# 注入 Makefile (从 888 目录物理复刻)
[ -f "888/atf-Makefile" ] && cp -f 888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
[ -f "888/uboot-Makefile" ] && cp -f 888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# 物理加固：注入 bl2_dev_spi_nor.c 补丁到 ATF files 目录，供 Makefile 调用
mkdir -p package/boot/arm-trusted-firmware-mediatek/files
[ -f "888/bl2_dev_spi_nor.c" ] && cp -f 888/bl2_dev_spi_nor.c package/boot/arm-trusted-firmware-mediatek/files/

# 注入内核定义与镜像打包逻辑 (适配 24.10 物理路径)
[ -f "888/filogic.mk" ] && cp -f 888/filogic.mk target/linux/mediatek/image/filogic.mk
[ -f "888/mt7981-sl-3000-emmc.dts" ] && cp -f 888/mt7981-sl-3000-emmc.dts target/linux/mediatek/dts/

# --- 3. 物理配置注入 ---
[ -f "888/sl3000.config" ] && cp -f 888/sl3000.config .config

# --- 4. 物理隔离：移除旧版包干扰 ---
# 强制移除 feeds 里的同名包，防止 OpenWrt 优先使用 feeds 导致注入失效
rm -rf package/feeds/devices/arm-trusted-firmware-mediatek
rm -rf package/feeds/devices/uboot-mediatek

echo "Physical Injection Complete."
