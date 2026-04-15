#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
# 最小物理修补：恢复 888 目录引用，确保与真实仓库路径对齐
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

# 最小物理修补：根据用户反馈修正 DTS 文件名变量
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证三件套文件是否存在 (原文照抄+最小修补) ==========
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

# ========== 准备 ImmortalWrt 源码 (原文照抄) ==========
echo "=== Preparing ImmortalWrt Source ==="
cp -r $SOURCE_DIR/immortalwrt $IMMORTALWRT_BUILD
cd $IMMORTALWRT_BUILD
echo "$IMMORTALWRT_BUILD" > $WORKSPACE/build-dir.txt

./scripts/feeds update -a
./scripts/feeds install -a

# ========== 物理注入 DTS (原文照抄+最小修补) ==========
cp -v $CONFIG_DIR/$DTS_NAME $DTS_PATH_OLD/
mkdir -p $DTS_PATH_NEW
cp -v $CONFIG_DIR/$DTS_NAME $DTS_PATH_NEW/

# ========== 注入设备定义 (原文照抄) ==========
cat >> $FILOGIC_MK << 'EOF'

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC
  DEVICE_DTS := mt7981b-sl3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_DRAM_SIZE := 1024M
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF

cp -v $CONFIG_DIR/sl3000.config .config
make defconfig
