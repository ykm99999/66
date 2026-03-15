#!/bin/bash

# $1 接收的是 888 目录的物理绝对路径
PART_DIR=$1

echo "--- [物理注入启动] ---"
echo "零件仓库 (888) 路径: $PART_DIR"
echo "当前源码工作空间: $(pwd)"

# --- 1. 物理清场 ---
# 移除会导致 Patch Failed 的底层冲突补丁
rm -rf package/boot/arm-trusted-firmware-mediatek/patches/*
rm -rf package/boot/uboot-mediatek/patches/*

# --- 2. 物理搬运核心零件 ---
# 搬运 Makefile 到对应包目录
cp -f "$PART_DIR/atf-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
cp -f "$PART_DIR/uboot-Makefile" package/boot/uboot-mediatek/Makefile

# 搬运 DTS 硬件定义
mkdir -p target/linux/mediatek/dts/
cp -f "$PART_DIR/mt7981-sl-3000-emmc.dts" target/linux/mediatek/dts/

# 注入固件生成规则
cat "$PART_DIR/filogic.mk" >> target/linux/mediatek/image/filogic.mk

# --- 3. 像素级名称修正 ---
# 确保 filogic.mk 里的 mt7981-sl3000 与你的 DTS 文件名完全一致
find target/linux/mediatek/image/ -name "*.mk" -exec sed -i 's/mt7981-sl3000/mt7981-sl-3000-emmc/g' {} +

echo "--- [物理链路] 注入已完成 ---"
