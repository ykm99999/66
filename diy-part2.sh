#!/bin/bash

# --- 工序 4: 物理路径绝对溯源 ---
PATCH_DIR="${GITHUB_WORKSPACE}/888"
OPENWRT_ROOT=$(pwd)
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
echo "物理执行：工序 6 - 注入 Web 192.168.1.1 救砖零件"

# --- 工序 7: 物理网口逻辑修正 ---
NETWORK_FILE="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if [ -f "$NETWORK_FILE" ]; then
    sed -i '/sl,3000-emmc/d' "$NETWORK_FILE"
    sed -i '/casat,ar3000m/a \\tsl,3000-emmc)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;' "$NETWORK_FILE"
fi
echo "物理执行：工序 7 - DTS 逻辑与网口拓扑物理对齐"

# --- 工序 8: 物理分区锁定 (针对 32MB NOR 修复) ---
# 准则 3 诊断：强制注入分区大小，确保在 3000 行配置中物理生效
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=6" >> .config

sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=20" >> .config

# --- 工序 9: 核心驱动补全 ---
# 物理锁定 eMMC 驱动，防止在几千行配置中被误删
sed -i '/CONFIG_PACKAGE_kmod-mmc/d' .config
echo "CONFIG_PACKAGE_kmod-mmc=y" >> .config
sed -i '/CONFIG_PACKAGE_kmod-mtk-sd/d' .config
echo "CONFIG_PACKAGE_kmod-mtk-sd=y" >> .config

echo "物理执行：工序 8 & 9 - 32MB 分区布局与存储驱动物理锁定完成"
