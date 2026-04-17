#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

# 物理修正：对齐仓库实际文件名
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware

echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/$DTS_NAME" ]; then
    echo "❌ 缺少 $CONFIG_DIR/$DTS_NAME"
    exit 1
fi

# 准备源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 更新 Feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 注册设备 (禁用 EOF，物理注入)
echo "" >> $FILOGIC_MK
echo "define Device/sl_3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_VENDOR := SL" >> $FILOGIC_MK
echo "  DEVICE_MODEL := 3000 eMMC (1GB)" >> $FILOGIC_MK
echo "  DEVICE_DTS := mt7981b-sl3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> $FILOGIC_MK
echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_PACKAGES := kmod-usb3 kmod-usb-storage kmod-mmc luci-app-passwall2 xray-core docker-ce" >> $FILOGIC_MK
echo "  IMAGES := sysupgrade.bin" >> $FILOGIC_MK
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> $FILOGIC_MK
echo "endef" >> $FILOGIC_MK
echo "TARGET_DEVICES += sl_3000-emmc" >> $FILOGIC_MK

cp -v $CONFIG_DIR/sl3000.config .config
make defconfig
echo $PWD > $WORKSPACE/build-dir.txt
