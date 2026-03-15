#!/bin/bash

# 获取传入的零件库路径 (config_repo)
PART_REPO=$1

if [ -z "$PART_REPO" ]; then
    echo "Error: Part repository path not provided."
    exit 1
fi

echo "--- [物理链路诊断] ---"
echo "正在从零件库搬运: $PART_REPO/888"
echo "当前源码位置: $(pwd)"

# --- 1. 物理清场 (斩草除根) ---
# 删除底层仓库自带的、会导致编译冲突的 patches
rm -rf package/boot/arm-trusted-firmware-mediatek/patches/*
rm -rf package/boot/uboot-mediatek/patches/*

# --- 2. 零件搬运：ATF 与 U-Boot ---
cp -f "$PART_REPO/888/atf-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
cp -f "$PART_REPO/888/uboot-Makefile" package/boot/uboot-mediatek/Makefile

# --- 3. 零件搬运：DTS 与 镜像规则 ---
mkdir -p target/linux/mediatek/dts/
cp -f "$PART_REPO/888/mt7981-sl-3000-emmc.dts" target/linux/mediatek/dts/
cat "$PART_REPO/888/filogic.mk" >> target/linux/mediatek/image/filogic.mk

# --- 4. 物理修正：全局名称对齐 ---
# 将 mk 文件中可能存在的 mt7981-sl3000 统一修正为你的 DTS 文件名
find target/linux/mediatek/image/ -name "*.mk" -exec sed -i 's/mt7981-sl3000/mt7981-sl-3000-emmc/g' {} +

echo "--- [物理注入] 零件已就位，补丁已清理 ---"
