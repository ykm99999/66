#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V22 ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"

echo "### 物理执行：V22 核心架构强制改写 ###"

# 1. 动态定位并清理 MediaTek 架构
TARGET_DIR=$(find target/linux -name "mediatek" -type d | head -n 1)
[ -z "$TARGET_DIR" ] && TARGET_DIR="target/linux/mediatek"

# 物理重置子架构：彻底删除 MT7622/MT7623，只允许 filogic 存在
echo "SUBTARGETS:=filogic" > $TARGET_DIR/Makefile
cat >> $TARGET_DIR/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 2. 物理注入核心镜像定义 (剥离冲突依赖)
MK_FILE="$TARGET_DIR/image/filogic.mk"
mkdir -p $(dirname "$MK_FILE")
# 抓取上游定义
curl -sL "$RAW_URL/target/linux/mediatek/image/mt7981.mk" -o "$MK_FILE"

# 【核心物理改写】
# a. 物理删除所有会导致 Kconfig 校验失败的高级插件，只留最基础驱动
sed -i 's/DEVICE_PACKAGES :=.*/DEVICE_PACKAGES := kmod-fs-f2fs kmod-mmc/' "$MK_FILE"
# b. 强制排他性赋值，确保不含 BPI-R64 等默认设备
sed -i 's/TARGET_DEVICES +=/TARGET_DEVICES :=/g' "$MK_FILE"
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> "$MK_FILE"

# 3. 物理注入 DTS (全路径覆盖)
DTS_NAME="mt7981-sl-3000-emmc.dts"
find $TARGET_DIR -name "dts" -type d | while read dts_path; do
    dest_dts="$dts_path/mediatek/$DTS_NAME"
    mkdir -p $(dirname "$dest_dts")
    curl -sL "$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/$DTS_NAME" -o "$dest_dts"
done

# 4. 物理修改全局默认值：将默认架构从 x86 强行修改为 mediatek
# 这一步是为了防止 oldconfig 在找不到目标时自动跳回 x86
sed -i 's/default "x86"/default "mediatek"/' target/config/Config-build.in

# 5. 物理强制初始化极简 .config
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：V22 架构强攻注入完成。"
