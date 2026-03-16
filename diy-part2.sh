#!/bin/bash

# --- 工序 4: 物理路径绝对溯源 ---
PATCH_DIR="${GITHUB_WORKSPACE}/888"
echo "物理执行：工序 4 - 锁定补丁集绝对路径 $PATCH_DIR"

# --- 工序 10: 物理切除递归依赖癌细胞 (彻底解决 rd05a1 报错) ---
# 必须物理删除该文件夹，否则 Kconfig 会在扫描阶段崩溃
echo "物理执行：工序 10 - 物理切除冲突零件 rd05a1"
find package/ -name "*rd05a1*" -exec rm -rf {} + || true

# --- 工序 11: 物理矫正 Target 架构 (彻底解决 MT7622 错误与 args.h 缺失) ---
# 强制将编译器物理引向 MT7981 Filogic 核心
echo "物理执行：工序 11 - 强行锁定编译目标为 MT7981 SL3000"
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_casat_sl3000-emmc/d' .config

echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_casat_sl3000-emmc=y" >> .config

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
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=6" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=20" >> .config

# --- 工序 9: 物理补全核心驱动 ---
sed -i '/CONFIG_PACKAGE_kmod-mmc/d' .config
sed -i '/CONFIG_PACKAGE_kmod-mtk-sd/d' .config
echo "CONFIG_PACKAGE_kmod-mmc=y" >> .config
echo "CONFIG_PACKAGE_kmod-mtk-sd=y" >> .config

echo "物理定论：架构已校准，递归已切除，32MB 分区表物理锁定完成"
