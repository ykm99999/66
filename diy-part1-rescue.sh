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

# 验证 DTS
echo "=== 验证 DTS ==="
if [ ! -f "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981b-sl3000-emmc.dts"
    exit 1
fi
echo "✅ DTS 存在"

# 准备 ImmortalWrt 源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置（禁用 telephony，不添加 passwall）
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 删除问题包（不影响救砖）
PROBLEM_PKGS="
aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark
pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server
gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav
dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing
kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl
python-rpds-py python-service-identity python-twisted python-docker
python-jsonschema python-jsonschema-specifications python-referencing
onionshare-cli onionshare weston wpewebkit libextractor python-bcrypt python-cryptography
python-maturin podman ruby-yaml
"
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

# 删除 mt76 无线驱动（救砖不需要）
if [ -d package/kernel/mt76 ]; then
    rm -rf package/kernel/mt76
    echo "✅ 已删除 mt76"
fi

# 注册设备树
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# 注入救砖设备定义（只包含救砖设备）
cat >> $FILOGIC_MK << 'EOF'

define Device/sl_3000-spi-nor
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (32MB)
  DEVICE_DTS := mt7981b-sl3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi-nor
  DEVICE_PACKAGES := \
    block-mount \
    uboot-envtools
  IMAGES := sysupgrade.bin
  IMAGE_SIZE := 25600k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-spi-nor
EOF
echo "✅ 救砖设备定义已注入"

# 复制救砖配置
cp -v $CONFIG_DIR/sl3000-rescue.config .config || exit 1

# 强制启用平台和救砖设备
sed -i '/CONFIG_TARGET_mediatek/d' .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 生成配置
make defconfig || exit 1
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

make oldconfig || exit 1
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 验证
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备未启用"
    exit 1
fi
echo "✅ 救砖设备已启用"

echo $PWD > $WORKSPACE/build-dir.txt
