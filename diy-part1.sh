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

# 物理修正：对齐仓库实际文件名
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证三件套文件是否存在 ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/$DTS_NAME" ]; then
    echo "❌ 缺少 $CONFIG_DIR/$DTS_NAME"
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

# 修改 feeds 配置
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1

# ========== 注册三件套（设备树注入） ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/$DTS_NAME $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/$DTS_NAME $DTS_PATH_NEW/ || exit 1

# 写入设备定义 (禁用 EOF，使用 echo)
echo "" >> $FILOGIC_MK
echo "define Device/sl_3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_VENDOR := SL" >> $FILOGIC_MK
echo "  DEVICE_MODEL := 3000 eMMC (1GB)" >> $FILOGIC_MK
echo "  DEVICE_DTS := ${DTS_NAME%.*}" >> $FILOGIC_MK
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> $FILOGIC_MK
echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_PACKAGES := kmod-usb3 kmod-usb-storage kmod-usb-storage-uas f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc luci-app-ksmbd luci-app-passwall2 xray-core chinadns-ng docker-ce luci-app-dockerman" >> $FILOGIC_MK
echo "  IMAGES := sysupgrade.bin" >> $FILOGIC_MK
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> $FILOGIC_MK
echo "endef" >> $FILOGIC_MK
echo "TARGET_DEVICES += sl_3000-emmc" >> $FILOGIC_MK

# 注入基础配置
cp -v $CONFIG_DIR/sl3000.config .config || exit 1
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

make defconfig || exit 1
make -j1 V=s oldconfig || exit 1

echo $PWD > $WORKSPACE/build-dir.txt
echo "✅ diy-part1.sh 物理修复完成"
