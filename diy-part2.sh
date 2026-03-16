#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V12 ---
[ -d "${GITHUB_WORKSPACE}/888" ] && PATCH_DIR="${GITHUB_WORKSPACE}/888" || PATCH_DIR="../888"

echo "物理重构：正在物理干预源码树..."

# 1. 物理抹除所有干扰子架构
# 直接重写 Makefile，把 SUBTARGETS 焊死在 filogic 上
echo "SUBTARGETS:=filogic" > target/linux/mediatek/Makefile
cat >> target/linux/mediatek/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 2. 物理注入硬件定义（强制成为该架构的唯一设备）
if [ -f "$PATCH_DIR/mt7981.mk" ]; then
    # 物理清空原有的所有设备定义，只注入你的 SL3000
    cat "$PATCH_DIR/mt7981.mk" > target/linux/mediatek/image/filogic.mk
    # 强行追加：确保系统只认这一个设备
    echo 'TARGET_DEVICES := sl_3000-emmc' >> target/linux/mediatek/image/filogic.mk
fi

# 3. 物理重写 .config (原子级强制，不使用追加)
# 我们直接生成一个“没得选”的配置文件
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
# 物理封锁 Default 路径
# CONFIG_TARGET_mediatek_filogic_Default is not set
EOF

# 4. 物理对齐：修改内核分区表的源码默认值（救砖红线最后一道防线）
# 即使配置失效，也要让生成的固件物理大小正确
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

echo "物理定论：V12 脚本已完成物理强占。系统已被迫认领 sl_3000-emmc。"
