#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V22-Final ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"

echo "### 物理执行：V22 核心架构强制改写 ###"

# 1. 动态定位并物理净化架构目录
TARGET_DIR=$(find target/linux -name "mediatek" -type d | head -n 1)
[ -z "$TARGET_DIR" ] && TARGET_DIR="target/linux/mediatek"

# 强制重置子架构：物理切断 MT7622/MT7623 的路径
echo "SUBTARGETS:=filogic" > $TARGET_DIR/Makefile
cat >> $TARGET_DIR/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 2. 物理注入核心镜像定义 (MK)
MK_FILE="$TARGET_DIR/image/filogic.mk"
mkdir -p $(dirname "$MK_FILE")
curl -sL "$RAW_URL/target/linux/mediatek/image/mt7981.mk" -o "$MK_FILE"

# 物理强行赋值，确保排他性，剥离复杂依赖防止校验失败
sed -i 's/DEVICE_PACKAGES :=.*/DEVICE_PACKAGES := kmod-fs-f2fs kmod-mmc/' "$MK_FILE"
sed -i 's/TARGET_DEVICES +=/TARGET_DEVICES :=/g' "$MK_FILE"
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> "$MK_FILE"

# 3. 物理注入设备树 (DTS) - 全路径覆盖
DTS_NAME="mt7981-sl-3000-emmc.dts"
find $TARGET_DIR -name "dts" -type d | while read dts_path; do
    dest_dts="$dts_path/mediatek/$DTS_NAME"
    mkdir -p $(dirname "$dest_dts")
    curl -sL "$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/$DTS_NAME" -o "$dest_dts"
done

# 4. 修改全局 Kconfig 默认值，物理阻止漂移回 x86
sed -i 's/default "x86"/default "mediatek"/' target/config/Config-build.in

echo "物理定论：架构强攻脚本执行完毕。"
