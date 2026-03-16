#!/bin/bash

# --- 工序 4: 物理路径绝对溯源 ---
PATCH_DIR="${GITHUB_WORKSPACE}/888"
echo "物理执行：工序 4 - 锁定补丁集绝对路径 $PATCH_DIR"

# --- 工序 5: 物理零件注入 (ATF/U-Boot/MK) ---
rm -rf package/boot/arm-trusted-firmware-mediatek
mkdir -p package/boot/arm-trusted-firmware-mediatek

[ -f "$PATCH_DIR/atf-Makefile" ] && cp -f "$PATCH_DIR/atf-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
[ -f "$PATCH_DIR/uboot-Makefile" ] && cp -f "$PATCH_DIR/uboot-Makefile" package/boot/uboot-mediatek/Makefile
[ -f "$PATCH_DIR/mt7981.mk" ] && cp -f "$PATCH_DIR/mt7981.mk" target/linux/mediatek/image/mt7981.mk

# --- 工序 6: Web 救砖配置注入 ---
mkdir -p package/boot/uboot-mediatek/files
[ -f "$PATCH_DIR/mt7981_sl3000_nor_defconfig" ] && cp -f "$PATCH_DIR/mt7981_sl3000_nor_defconfig" package/boot/uboot-mediatek/files/

# --- 工序 8: 彻底锁定分区布局 (32MB NOR) ---
# 物理诊断：先删除现有定义，防止重复或冲突
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
# 物理强制写入正确数值
echo "CONFIG_TARGET_KERNEL_PARTSIZE=6" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=20" >> .config

# --- 工序 9: 彻底锁定核心驱动 ---
sed -i '/CONFIG_PACKAGE_kmod-mmc/d' .config
sed -i '/CONFIG_PACKAGE_kmod-mtk-sd/d' .config
echo "CONFIG_PACKAGE_kmod-mmc=y" >> .config
echo "CONFIG_PACKAGE_kmod-mtk-sd=y" >> .config

echo "物理定论：分区与驱动逻辑已完成物理二次校准"
