#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V21 ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"

echo "### 物理执行：V21 架构净化与排他性锁定 ###"

# 1. 动态定位并物理接管架构 Makefile
TARGET_DIR=$(find target/linux -name "mediatek" -type d | head -n 1)
[ -z "$TARGET_DIR" ] && TARGET_DIR="target/linux/mediatek"

# 【关键】物理重写 SUBTARGETS，从源码根源抹除 MT7622
echo "SUBTARGETS:=filogic" > $TARGET_DIR/Makefile
cat >> $TARGET_DIR/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 2. 物理注入核心零件 (MK 和 DTS)
MK_FILE="$TARGET_DIR/image/filogic.mk"
mkdir -p $(dirname "$MK_FILE")
# 抓取上游定义并强制设为唯一设备
curl -sL "$RAW_URL/target/linux/mediatek/image/mt7981.mk" -o "$MK_FILE"
sed -i 's/TARGET_DEVICES +=/TARGET_DEVICES :=/g' "$MK_FILE"
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> "$MK_FILE"

# 物理地毯式注入 DTS
DTS_NAME="mt7981-sl-3000-emmc.dts"
find $TARGET_DIR -name "dts" -type d | while read dts_path; do
    curl -sL "$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/$DTS_NAME" -o "$dts_path/mediatek/$DTS_NAME"
done

# 3. 物理初始化 .config (显式禁用所有干扰项)
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
# CONFIG_TARGET_mediatek_mt7622 is not set
# CONFIG_TARGET_mediatek_mt7986 is not set
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：V21 架构净化已完成。"
