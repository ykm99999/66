#!/bin/bash

# --- 旗舰工厂：物理路径锁定 ---
PATCH_DIR="${GITHUB_WORKSPACE}/888"

# 1. 物理摘除递归包
find package/ -name "*rd05a1*" -exec rm -rf {} + || true

# 2. 物理校准 Target 真名 (sl_3000-emmc)
sed -i '/CONFIG_TARGET/d' .config
{
  echo "CONFIG_TARGET_mediatek=y"
  echo "CONFIG_TARGET_mediatek_filogic=y"
  echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y"
} >> .config

# 3. 物理零件注入 (ATF/U-Boot/MK)
# 必须覆盖 target/linux/mediatek/image/filogic.mk 
# 确保里面包含能够生成 nor-programmer-dump.bin 的定义
rm -rf package/boot/arm-trusted-firmware-mediatek
mkdir -p package/boot/arm-trusted-firmware-mediatek
[ -f "$PATCH_DIR/atf-Makefile" ] && cp -f "$PATCH_DIR/atf-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
[ -f "$PATCH_DIR/uboot-Makefile" ] && cp -f "$PATCH_DIR/uboot-Makefile" package/boot/uboot-mediatek/Makefile
[ -f "$PATCH_DIR/mt7981.mk" ] && cp -f "$PATCH_DIR/mt7981.mk" target/linux/mediatek/image/mt7981.mk

# 4. 强力锁定分区表 (解决救砖溢出问题)
sed -i '/CONFIG_TARGET_KERNEL_PARTSIZE/d' .config
sed -i '/CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config
echo "CONFIG_TARGET_KERNEL_PARTSIZE=6" >> .config
echo "CONFIG_TARGET_ROOTFS_PARTSIZE=20" >> .config

echo "物理定论：V6.1 生产线已就绪，标识符已锁定为 sl_3000-emmc。"
