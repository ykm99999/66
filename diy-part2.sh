#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V20 ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"

echo "### 物理执行：V20 路径穿透与镜像对齐 ###"

# 1. 物理修正：定位真正的 mediatek 目录
# 有些仓库路径是 target/linux/mediatek，有些是 target/linux/mediatek_mt7981
TARGET_DIR=$(find target/linux -name "mediatek*" -type d | head -n 1)
echo "目标物理路径确认: $TARGET_DIR"

# 2. 物理强力拉取 MK 定义
# 我们不创建新文件，我们直接寻找现有的 .mk 文件并暴力覆盖它
MK_FILE=$(find $TARGET_DIR -name "mt7981.mk" -o -name "filogic.mk" | head -n 1)
if [ -z "$MK_FILE" ]; then
    MK_FILE="$TARGET_DIR/image/filogic.mk"
    mkdir -p $(dirname "$MK_FILE")
fi
echo "物理注入镜像定义至: $MK_FILE"
curl -sL "$RAW_URL/target/linux/mediatek/image/mt7981.mk" -o "$MK_FILE"

# 3. 物理注入 DTS (核心零件)
DTS_DIR=$(find $TARGET_DIR -name "mediatek" -type d | grep "files" | head -n 1)
[ -z "$DTS_DIR" ] && DTS_DIR="$TARGET_DIR/files-5.4/arch/arm64/boot/dts/mediatek"
mkdir -p "$DTS_DIR"
curl -sL "$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts" -o "$DTS_DIR/mt7981-sl-3000-emmc.dts"
echo "物理注入 DTS 至: $DTS_DIR"

# 4. 物理修改 Makefile：强行把我们的设备塞进编译链
# 无论上游 Makefile 怎么写，我们强行在末尾追加
echo -e "\nTARGET_DEVICES += sl_3000-emmc" >> "$MK_FILE"

# 5. 物理重写 .config
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：V20 零件已完成物理渗透。"
