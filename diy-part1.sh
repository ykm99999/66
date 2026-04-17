#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
CONFIG_DIR="$MAIN_REPO/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
DTS_NAME="mt7981-sl-3000-emmc.dts"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

echo "=== diy-part1: 配置 ImmortalWrt 编译环境 ==="

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware,parts}
cd "$WORKSPACE"

# 复制 ImmortalWrt 源码
rm -rf immortalwrt-build
cp -r "$MAIN_REPO/immortalwrt" immortalwrt-build
cd immortalwrt-build

# 更新 feeds
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a
./scripts/feeds install -a

# 删除问题包 (精简)
for pkg in aardvark-dns netavark podman rust rust-bindgen python-jsonschema; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
rm -rf feeds/video feeds/telephony

./scripts/feeds update -i
./scripts/feeds install -a

# 复制设备树
mkdir -p target/linux/mediatek/dts
cp -v "$CONFIG_DIR/$DTS_NAME" target/linux/mediatek/dts/

# 添加设备定义到 filogic.mk（防重复）
if ! grep -q "sl_3000-emmc" "$FILOGIC_MK"; then
    cat >> "$FILOGIC_MK" <<'EOF'

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := kmod-usb3 kmod-usb-storage kmod-mmc luci-app-passwall2 xray-core docker-ce
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF
fi

# 复制配置文件并启用设备
cp -v "$CONFIG_DIR/sl3000.config" .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

make defconfig
make -j1 V=s oldconfig

# 验证设备已启用
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config || {
    echo "❌ 设备未在 .config 中启用"
    exit 1
}

echo "$PWD" > "$WORKSPACE/build-dir.txt"
echo "✅ diy-part1 完成"
