#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V10 ---
# 自动识别 PATCH 路径（兼容本地与 Actions 环境）
[ -d "${GITHUB_WORKSPACE}/888" ] && PATCH_DIR="${GITHUB_WORKSPACE}/888" || PATCH_DIR="../888"

echo "物理自检：正在清理递归冲突包..."
find package/ -name "*rd05a1*" -exec rm -rf {} + || true

echo "物理强占：正在抹除 MT7622 干扰..."
# 修改 Mediatek 主 Makefile，强制只允许编译 filogic
sed -i 's/SUBTARGETS:=.*/SUBTARGETS:=filogic/' target/linux/mediatek/Makefile

echo "物理注入：覆盖硬件定义并强制注册..."
# 1. 物理覆盖硬件定义文件
if [ -f "$PATCH_DIR/mt7981.mk" ]; then
    cp -f "$PATCH_DIR/mt7981.mk" target/linux/mediatek/image/mt7981.mk
    # 2. 物理强行关联：确保主 Makefile 引用此定义
    # 查找 filogic.mk 或 mt7981.mk 并注入真名注册
    TARGET_MK="target/linux/mediatek/image/filogic.mk"
    [ ! -f "$TARGET_MK" ] && TARGET_MK="target/linux/mediatek/image/mt7981.mk"
    echo 'TARGET_DEVICES += sl_3000-emmc' >> "$TARGET_MK"
fi

echo "物理对齐：原子化配置注入..."
# 强制覆盖当前 .config，不留漂移余地
sed -i '/CONFIG_TARGET/d' .config
{
  echo "CONFIG_TARGET_mediatek=y"
  echo "CONFIG_TARGET_mediatek_filogic=y"
  echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y"
  echo "CONFIG_TARGET_KERNEL_PARTSIZE=6"
  echo "CONFIG_TARGET_ROOTFS_PARTSIZE=20"
} >> .config

# 锁定 20MB 救砖空间
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

echo "物理定论：V10 脚本已完成源码层级强占。"
