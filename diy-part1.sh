#!/bin/bash
# diy-part1.sh
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
CONFIG_DIR="$MAIN_REPO/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"

DEVICE_NAME="mt7981_sl3000_spi_rescue"
DTS_FILE="mt7981b-sl3000-emmc.dts"

echo "=== diy-part1: 配置 ImmortalWrt 环境 ==="

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware,parts}

cd "$WORKSPACE"
rm -rf immortalwrt-build
cp -r "$MAIN_REPO/immortalwrt" immortalwrt-build
cd immortalwrt-build

# 更新 feeds
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

# 删除问题包
for pkg in aardvark-dns netavark podman rust rust-bindgen python-jsonschema; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
rm -rf feeds/video feeds/telephony
./scripts/feeds update -i
./scripts/feeds install -a

# 复制设备树
mkdir -p target/linux/mediatek/dts
cp -v "$CONFIG_DIR/$DTS_FILE" target/linux/mediatek/dts/
mkdir -p target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek
cp -v "$CONFIG_DIR/$DTS_FILE" target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/

# 使用三件套中的 Makefile（设备定义）
cp -v "$CONFIG_DIR/mt7981_sl3000.mk" target/linux/mediatek/image/filogic.mk

# 复制配置文件并启用设备
cp -v "$CONFIG_DIR/sl3000.config" .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y" >> .config

make defconfig
make -j1 V=s oldconfig

grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y" .config || {
    echo "❌ 设备未在 .config 中启用"
    exit 1
}

echo "$PWD" > "$WORKSPACE/build-dir.txt"
echo "✅ diy-part1 完成"
