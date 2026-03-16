#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V18 ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"
DTS_SOURCE="$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
MK_SOURCE="$RAW_URL/target/linux/mediatek/image/mt7981.mk"

echo "### 物理执行：V18 核弹级物理强占 ###"

# 1. 物理清空除 MediaTek 以外的所有架构（彻底断掉回退 x86 的路）
find target/linux/ -maxdepth 1 -mindepth 1 -not -name "mediatek" -not -name "Makefile" -exec rm -rf {} +

# 2. 物理抓取并地毯式注入核心零件
curl -sL "$DTS_SOURCE" -o /tmp/sl3000.dts
curl -sL "$MK_SOURCE" -o /tmp/sl3000.mk

# 注入 DTS
find target/linux/mediatek/ -type d -name "files*" | while read dir; do
    dest="$dir/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts"
    mkdir -p $(dirname "$dest")
    cp /tmp/sl3000.dts "$dest"
done

# 3. 物理重写子架构定义，强行关联
echo "SUBTARGETS:=filogic" > target/linux/mediatek/Makefile
cat >> target/linux/mediatek/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 4. 物理强制镜像定义
cat /tmp/sl3000.mk > target/linux/mediatek/image/filogic.mk
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> target/linux/mediatek/image/filogic.mk

# 5. 物理锁定内核 Config (5.4 专供)
# 强制让 MediaTek 成为全局唯一默认值
sed -i 's/default "x86"/default "mediatek"/' target/config/Config-build.in

# 6. 生成物理不可逃逸的 .config
cat > .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
CONFIG_TARGET_KERNEL_PARTSIZE=6
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：V18 架构已物理唯一化。系统已无处可逃。"
