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

# ========== 验证三件套文件是否存在 ==========
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
echo "=== Preparing ImmortalWrt Source ==="
cp -r $SOURCE_DIR/immortalwrt $IMMORTALWRT_BUILD
cd $IMMORTALWRT_BUILD

# 记录路径供 part2 使用
echo "$IMMORTALWRT_BUILD" > $WORKSPACE/build-dir.txt

# 修改 feeds 并同步
sed -i 's/.*telephony.*/#&/' feeds.conf.default
echo "src-git passwall https://github.com/xiaorouji/openwrt-passwall;main" >> feeds.conf.default
echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages;main" >> feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

# ========== 物理注入 DTS 与设备定义 ==========
echo "=== Injecting DTS & Device Definitions ==="
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/
mkdir -p $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/

# 原文复刻：追加设备定义到 filogic.mk
cat >> $FILOGIC_MK << 'EOF'

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC
  DEVICE_DTS := mt7981b-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_DRAM_SIZE := 1024M
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    luci-app-passwall luci-app-passwall-codec luci-app-passwall-v2ray-geodata \
    docker-ce docker-compose kmod-br-netfilter kmod-ikconfig kmod-ipt-physdev \
    kmod-nf-ipt6 kmod-nf-ipvs kmod-veth kmod-fs-overlay luci-app-dockerman
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF

# 验证注入
if ! grep -q "sl_3000-emmc" $FILOGIC_MK; then
    echo "❌ 设备定义未成功写入 $FILOGIC_MK"
    exit 1
fi

cp -v $CONFIG_DIR/sl3000.config .config
make defconfig
