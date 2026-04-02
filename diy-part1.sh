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
FILOGIC_MK="$IMMORTALWRT_BUILD/target/linux/mediatek/image/filogic.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# 验证配置文件
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981-sl-3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981-sl-3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000-mini.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000-mini.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# 准备源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 简化 feeds（只保留基础，移除 passwall）
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
# 注释掉 passwall 相关 feed（避免依赖问题）
sed -i '/passwall/d' feeds.conf.default

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 注册设备树
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# 注入救砖设备定义
mkdir -p "$(dirname "$FILOGIC_MK")"
cat >> "$FILOGIC_MK" << 'EOF'

define Device/sl_3000-spi-nor
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (32MB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi-nor
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage \
    block-mount \
    uboot-envtools
  IMAGES := sysupgrade.bin
  IMAGE_SIZE := 32768k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-spi-nor
EOF

# 复制极简配置
cp -v $CONFIG_DIR/sl3000-mini.config .config || exit 1

# 启用平台和救砖设备
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

make defconfig || exit 1
make oldconfig || exit 1

echo "✅ 救砖设备已启用"
echo $PWD > $WORKSPACE/build-dir.txt
