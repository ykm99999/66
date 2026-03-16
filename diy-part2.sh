#!/bin/bash

# --- 物理执行准则：路径锁定 ---
PATCH_DIR="${GITHUB_WORKSPACE}/888"

# --- 工序 1: 物理切除递归依赖冲突 ---
# 彻底删除 rd05a1，防止 Kconfig 引擎因为逻辑死循环重置配置
find package/ -name "*rd05a1*" -exec rm -rf {} + || true

# --- 工序 2: 物理锁定 Target 架构 (解决 MT7622 与 args.h 报错) ---
# 无论 .config 原来写的是什么，全部物理抹除并强制写入 MT7981
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_casat_sl3000-emmc/d' .config

echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_casat_sl3000-emmc=y" >> .config

# --- 工序 3: 物理零件注入 (ATF/U-Boot/MK) ---
rm -rf package/boot/arm-trusted-firmware-mediatek
mkdir -p package/boot/arm-trusted-firmware-mediatek
[ -f "$PATCH_DIR/atf-Makefile" ] && cp -f "$PATCH_DIR/atf-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
[ -f "$PATCH_DIR/uboot-Makefile" ] && cp -f "$PATCH_DIR/uboot-Makefile" package/boot/uboot-mediatek/Makefile
[ -f "$PATCH_DIR/mt7981.mk" ] && cp -f "$PATCH_DIR/mt7981.mk" target/linux/mediatek/image/mt7981.mk

mkdir -p package/boot/uboot-mediatek/files
[ -f "$PATCH_DIR/mt7981_sl3000_nor_defconfig" ] && cp -f "$PATCH_DIR/mt7981_sl3000_nor_defconfig" package/boot/uboot-mediatek/files/

# --- 工序 4: 物理锁定 32MB 分区布局 ---
# 内核 6MB + 系统 20MB = 救砖黄金比例
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=6" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=20" >> .config

# --- 工序 5: 物理补全核心驱动 ---
sed -i '/CONFIG_PACKAGE_kmod-mmc/d' .config
sed -i '/CONFIG_PACKAGE_kmod-mtk-sd/d' .config
echo "CONFIG_PACKAGE_kmod-mmc=y" >> .config
echo "CONFIG_PACKAGE_kmod-mtk-sd=y" >> .config

# --- 工序 6: 屏蔽干扰包 ---
# 屏蔽通用 u-boot 防止干扰 MTK 专用版
sed -i '/PACKAGE_u-boot/d' .config
echo "# CONFIG_PACKAGE_u-boot is not set" >> .config

echo "物理定论：全链路溯源纠偏完成，Target 锁定为 MT7981 SL3000。"
