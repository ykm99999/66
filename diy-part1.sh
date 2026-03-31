#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
# 物理对齐：目标路径需涵盖 6.6 内核路径
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 验证三件套 (物理名称对齐) ==========
echo "=== 验证配置文件 ==="
# 统一使用不带后缀的名称，方便脚本逻辑切换
if [ ! -f "$CONFIG_DIR/mt7981-sl-3000.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981-sl-3000.dts"
    exit 1
fi
echo "✅ 配置文件齐全"

# ========== 2. 准备 ImmortalWrt 源码 ==========
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 禁用冲突 feeds 并添加 PassWall
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a && ./scripts/feeds install -a

# ========== 3. 注册三件套 (全链路物理注入) ==========
echo "=== 注入设备树与 Makefile 定义 ==="
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000.dts $DTS_PATH_OLD/
cp -v $CONFIG_DIR/mt7981-sl-3000.dts $DTS_PATH_NEW/

# 清除旧定义防止重复
sed -i '/sl_3000/d' $FILOGIC_MK 

# 物理注入：32MB SPI-NOR 救砖全家桶定义 [cite: 2026-03-30]
cat >> $FILOGIC_MK <<EOF

define Device/sl_3000-spi-32m
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (1GB)
  DEVICE_DTS := mt7981-sl-3000
  DEVICE_DTS_DIR := \$(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi
  DEVICE_DRAM_SIZE := 1024M
  DEVICE_PACKAGES := kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \\
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \\
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \\
    luci-app-passwall2 xray-core docker-ce luci-app-dockerman
  IMAGES := sysupgrade.bin Spi-flash-32MB.bin
  IMAGE_SIZE := 32768k
  IMAGE/Spi-flash-32MB.bin := \\
    append-u-boot-elf mt7981-bl2-nor | pad-to 3584k | \\
    append-u-boot-elf mt7981-fip-nor | pad-to 4096k | \\
    append-kernel | append-rootfs | pad-to 32768k | check-size
endef
TARGET_DEVICES += sl_3000-spi-32m
EOF

# ========== 4. 修正 .config 物理目标 ==========
cp -v $CONFIG_DIR/sl3000.config .config
# 强制覆盖为 SPI-32M 目标，否则不生成 32MB 包
sed -i 's/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y/# CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc is not set/' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-32m=y" >> .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config

# 禁用 EOF 原则：此处通过 cat 写入已完成，后续执行静默审计
make defconfig
make oldconfig

# ========== 5. 最终验证 ==========
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-32m=y" .config; then
    echo "❌ 物理目标切换失败！"
    exit 1
fi
echo "✅ 1GB SPI-32M 目标已激活"
echo $PWD > $WORKSPACE/build-dir.txt
