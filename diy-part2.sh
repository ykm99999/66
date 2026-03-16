#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V17 ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"
DTS_SOURCE="$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
MK_SOURCE="$RAW_URL/target/linux/mediatek/image/mt7981.mk"

echo "### 物理执行：V17 5.4内核物理锚定 ###"

# 1. 物理抓取核心零件
curl -sL "$DTS_SOURCE" -o /tmp/sl3000.dts
curl -sL "$MK_SOURCE" -o /tmp/sl3000.mk

# 2. 物理地毯式注入 DTS
# 遍历 mediatek 目录下所有 files 开头的文件夹，确保 DTS 物理存在
find target/linux/mediatek/ -type d -name "files*" | while read dir; do
    dest="$dir/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
    mkdir -p $(dirname "$dest")
    cp /tmp/sl3000.dts "$dest"
    echo "✅ DTS 物理锚定: $dest"
done

# 3. 物理强占 MK 镜像定义
# 覆盖 filogic.mk 并强制声明 sl_3000-emmc 是唯一合法设备
cat /tmp/sl3000.mk > target/linux/mediatek/image/filogic.mk
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> target/linux/mediatek/image/filogic.mk

# 4. 物理架构隔离
# 抹除 MT7622，让系统无路可退
echo "SUBTARGETS:=filogic" > target/linux/mediatek/Makefile
cat >> target/linux/mediatek/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 5. 物理注入 .config
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：V17 5.4内核物理锚点已焊死。"
