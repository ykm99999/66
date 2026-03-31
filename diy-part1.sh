#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
# 严格 1 版原文路径：不做任何多余层级添加
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证配置文件 (1 版原文) ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981-sl-3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981-sl-3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# ========== 准备 ImmortalWrt 源码 (1 版原文) ==========
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置 (1 版原文逻辑)
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }
./scripts/feeds install -a || { echo "❌ feeds install failed"; exit 1; }

# ========== 注册三件套 (1 版原文路径与注入方式) ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || { echo "❌ Failed to copy DTS"; exit 1; }
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || { echo "❌ Failed to copy DTS"; exit 1; }

# 物理修复：在原有 sl_3000-emmc 逻辑基础上，修正缝合定义
echo "" >> $FILOGIC_MK
echo "define Device/sl_3000-spi-32m" >> $FILOGIC_MK
echo "  DEVICE_VENDOR := SL" >> $FILOGIC_MK
echo "  DEVICE_MODEL := 3000 SPI-NOR (1GB)" >> $FILOGIC_MK
echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> $FILOGIC_MK
echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_DRAM_SIZE := 1024M" >> $FILOGIC_MK
echo "  DEVICE_PACKAGES := kmod-usb3 kmod-usb-storage kmod-usb-storage-uas f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils luci-app-passwall2 xray-core docker-ce luci-app-dockerman" >> $FILOGIC_MK
echo "  IMAGES := sysupgrade.bin Spi-flash-32MB.bin" >> $FILOGIC_MK
echo "  IMAGE/Spi-flash-32MB.bin := append-u-boot-elf mt7981-bl2-nor | pad-to 3584k | append-u-boot-elf mt7981-fip-nor | pad-to 4096k | append-kernel | append-rootfs | pad-to 32768k | check-size" >> $FILOGIC_MK
echo "endef" >> $FILOGIC_MK
echo "TARGET_DEVICES += sl_3000-spi-32m" >> $FILOGIC_MK

# ========== 最终修正 (1 版原文逻辑) ==========
cp -v $CONFIG_DIR/sl3000.config .config || { echo "❌ Failed to copy config"; exit 1; }
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
# 延续原文逻辑替换目标
sed -i 's/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-32m=y/' .config

make defconfig
echo $PWD > $WORKSPACE/build-dir.txt
