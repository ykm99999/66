#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# 验证配置文件
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981b-sl3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000-rescue.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000-rescue.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# 准备 ImmortalWrt 源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 删除问题包
PROBLEM_PKGS="aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl python-rpds-py python-service-identity python-twisted python-docker python-jsonschema python-jsonschema-specifications python-referencing onionshare-cli onionshare weston wpewebkit libextractor python-bcrypt python-cryptography python-maturin podman ruby-yaml"
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
rm -rf feeds/video feeds/telephony
rm -rf package/feeds
./scripts/feeds update -i || exit 1
./scripts/feeds install -a || exit 1
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
./scripts/feeds update -i || exit 1
make package/symlinks || exit 1

# 删除 mt76 驱动
if [ -d package/kernel/mt76 ]; then
    rm -rf package/kernel/mt76
    echo "✅ 已删除 mt76"
fi

# 复制设备树
mkdir -p $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts $DTS_PATH_NEW/ || exit 1
echo "✅ 设备树已复制"

# 将设备定义追加到 filogic.mk（不使用自定义镜像，依赖默认 initramfs）
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
cat >> $FILOGIC_MK << 'EOF'

define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := 1GB-DDR4-32MB-SPI-Rescue
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-nor
  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0
  KERNEL_LOADADDR := 0x40800000
  # 不定义 IMAGES，系统自动生成 initramfs-kernel.bin
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear \
    kmod-leds-gpio kmod-button-hotplug
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
EOF
echo "✅ 设备定义已追加"

# 复制配置
cp -v $CONFIG_DIR/sl3000-rescue.config .config || exit 1

# 清理并重新设置平台
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config

cat >> .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
EOF

make defconfig || exit 1

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
    echo "⚠️  Device not enabled, forcing..."
    echo "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" >> .config
    make oldconfig
fi

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 救砖设备已启用"

echo $PWD > $WORKSPACE/build-dir.txt
