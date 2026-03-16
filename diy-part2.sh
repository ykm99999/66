#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V19 ---
UPSTREAM_REPO="https://github.com/padavanonly/immortalwrt-mt798x-6.6"
UPSTREAM_BRANCH="2410"

echo "### 物理执行：V19 架构级全量置换 ###"

# 1. 物理删除本地已经损坏的架构树
rm -rf target/linux/mediatek

# 2. 从已知正常运行的上游仓库物理克隆 MediaTek 架构
git clone --depth 1 -b $UPSTREAM_BRANCH $UPSTREAM_REPO /tmp/upstream_repo
cp -r /tmp/upstream_repo/target/linux/mediatek target/linux/

# 3. 物理抓取并强制注入 SL3000 的专属 DTS
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"
DTS_SOURCE="$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"

# 确保 DTS 注入到每一个可能的 files 目录下
find target/linux/mediatek/ -type d -name "files*" | while read dir; do
    dest="$dir/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
    mkdir -p $(dirname "$dest")
    curl -sL "$DTS_SOURCE" -o "$dest"
done

# 4. 物理强制镜像 Makefile 锁定 SL3000
# 直接重置 filogic.mk，确保它不再 include 其他干扰项
MK_SOURCE="$RAW_URL/target/linux/mediatek/image/mt7981.mk"
curl -sL "$MK_SOURCE" > target/linux/mediatek/image/filogic.mk
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> target/linux/mediatek/image/filogic.mk

# 5. 物理锁定 .config
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：V19 架构置换已完成。SL3000 标识符现在具有物理原生合法性。"
