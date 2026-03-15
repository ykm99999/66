#!/bin/bash

# 获取主仓库的物理绝对路径
MAIN_REPO_PATH=$1

if [ -z "$MAIN_REPO_PATH" ]; then
    echo "Error: Physical path not provided. Usage: ./diy-part2.sh [path_to_repo]"
    exit 1
fi

echo "--- [物理链路] 正在从 $MAIN_REPO_PATH/888 搬运零件 ---"

# --- 1. 物理清场 ---
rm -rf package/boot/arm-trusted-firmware-mediatek/patches/*
rm -rf package/boot/uboot-mediatek/patches/*

# --- 2. 物理搬运：ATF ---
if [ -f "$MAIN_REPO_PATH/888/atf-Makefile" ]; then
    cp -f "$MAIN_REPO_PATH/888/atf-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
else
    echo "!!! 物理缺失: atf-Makefile !!!" && exit 1
fi

# --- 3. 物理搬运：U-Boot ---
if [ -f "$MAIN_REPO_PATH/888/uboot-Makefile" ]; then
    cp -f "$MAIN_REPO_PATH/888/uboot-Makefile" package/boot/uboot-mediatek/Makefile
else
    echo "!!! 物理缺失: uboot-Makefile !!!" && exit 1
fi

# --- 4. 物理注入：DTS 与 镜像规则 ---
mkdir -p target/linux/mediatek/dts/
cp -f "$MAIN_REPO_PATH/888/mt7981-sl-3000-emmc.dts" target/linux/mediatek/dts/
cat "$MAIN_REPO_PATH/888/filogic.mk" >> target/linux/mediatek/image/filogic.mk

# --- 5. 名称对齐修正 ---
find target/linux/mediatek/image/ -name "*.mk" -exec sed -i 's/mt7981-sl3000/mt7981-sl-3000-emmc/g' {} +

echo "--- [物理链路] diy-part2 执行完毕，全链路就位 ---"
