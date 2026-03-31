#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证配置文件 (严格原文照抄文件名) ==========
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

# ========== 准备 ImmortalWrt 源码 ==========
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置 (原文逻辑)
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a && ./scripts/feeds install -a

# ========== 注册三件套 (物理修复注入) ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/

# 注入设备定义：修正为 32MB 救砖缝合逻辑
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

# ========== 修正 .config 物理目标 ==========
cp -v $CONFIG_DIR/sl3000.config .config
sed -i 's/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-32m=y/' .config

make defconfig
echo $PWD > $WORKSPACE/build-dir.txt
