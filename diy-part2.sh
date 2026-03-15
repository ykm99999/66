#!/bin/bash

# --- 1. 物理清场：移除所有会导致 Patch failed 的旧补丁 ---
# 既然你已经手动删除了，这里作为自动化脚本的强制二次核验
rm -rf package/boot/arm-trusted-firmware-mediatek/patches/*
rm -rf package/boot/uboot-mediatek/patches/*

# --- 2. 物理注入：ATF 生产线劫持 ---
# 将 888 目录下的 atf-Makefile 覆盖到源码中
cp -f ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile

# --- 3. 物理注入：U-Boot 生产线劫持 ---
cp -f ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# --- 4. 物理注入：固件镜像生成规则 ---
cat ../888/filogic.mk >> target/linux/mediatek/image/filogic.mk

# --- 5. 物理注入：内核设备树 (DTS) ---
mkdir -p target/linux/mediatek/dts/
cp -f ../888/mt7981-sl-3000-emmc.dts target/linux/mediatek/dts/

# --- 6. 物理修正：全局名称统一 ---
# 确保所有的编译脚本都指向最新的 DTS 名称
find target/linux/mediatek/image/ -name "*.mk" -exec sed -i 's/mt7981-sl3000/mt7981-sl-3000-emmc/g' {} +

echo "--- [物理链路] diy-part2 执行完毕，零件已完全就位 ---"
