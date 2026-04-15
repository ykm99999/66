#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"

# 溯源诊断：精准对齐内核 6.6 的物理搜索路径
DTS_NAME="mt7981b-sl3000-emmc.dts"
DTS_DEST_TARGET="target/linux/mediatek/dts"
# 修正级联错误：确保文件存放在编译器真正访问的目录
DTS_DEST_KERNEL="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证配置文件 (原文照抄) ==========
echo "=== 验证配置文件 ==="
[ -f "$CONFIG_DIR/$DTS_NAME" ] || { echo "❌ 缺少 $DTS_NAME"; exit 1; }
[ -f "$CONFIG_DIR/sl3000.config" ] || { echo "❌ 缺少 sl3000.config"; exit 1; }
echo "✅ 配置文件齐全"

# ========== 准备源码 (原文照抄) ==========
echo "=== Preparing ImmortalWrt Source ==="
cp -r $SOURCE_DIR/immortalwrt/. $IMMORTALWRT_BUILD/
cd $IMMORTALWRT_BUILD
echo "$IMMORTALWRT_BUILD" > $WORKSPACE/build-dir.txt

./scripts/feeds update -a
./scripts/feeds install -a

# ========== 物理注入 DTS (2版路径修正) ==========
echo "=== Injecting DTS to Kernel Path ==="
mkdir -p "$DTS_DEST_TARGET"
mkdir -p "$DTS_DEST_KERNEL"
# 同时复制到 target 目录和 files 目录，并确保文件名像素级一致
cp -v "$CONFIG_DIR/$DTS_NAME" "$DTS_DEST_TARGET/mt7981b-sl3000-emmc.dts"
cp -v "$CONFIG_DIR/$DTS_NAME" "$DTS_DEST_KERNEL/mt7981b-sl3000-emmc.dts"

# ========== 注入设备定义 (原文照抄) ==========
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
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
