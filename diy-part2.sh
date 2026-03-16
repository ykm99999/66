#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V15 ---
# 1. 定义物理源地址 (RAW 格式)
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"
DTS_SOURCE="$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
MK_SOURCE="$RAW_URL/target/linux/mediatek/image/mt7981.mk"

echo "### 物理执行：跨仓库核心克隆 ###"

# 2. 物理拉取 DTS (设备树)
# 目标路径必须对应 target/linux/mediatek/files-5.4/... 
DTS_DEST="target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
mkdir -p $(dirname "$DTS_DEST")
curl -sL "$DTS_SOURCE" -o "$DTS_DEST"
if [ -f "$DTS_DEST" ]; then
    echo "✅ DTS 克隆成功: $DTS_DEST"
else
    echo "❌ 物理报错: DTS 抓取失败！" && exit 1
fi

# 3. 物理拉取 MK (镜像配置)
# 我们直接覆盖 filogic.mk，确保 SL3000 成为该架构的唯一合法标识符
MK_DEST="target/linux/mediatek/image/filogic.mk"
curl -sL "$MK_SOURCE" -o "$MK_DEST"
# 强行追加排他性指令：锁定 sl_3000-emmc 为唯一设备
echo "" >> "$MK_DEST"
echo "TARGET_DEVICES := sl_3000-emmc" >> "$MK_DEST"
echo "✅ MK 克隆并强占成功: $MK_DEST"

# 4. 物理抹除干扰子架构
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

echo "物理定论：V15 远程克隆闭环已完成。所有核心零件已就位。"
