#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware" "$STAGING_DIR_IMAGE"

# ========== 验证配置文件 ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981b-sl3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# ========== 准备 ImmortalWrt 源码 ==========
cd "$WORKSPACE"
rm -rf immortalwrt-build
cp -r immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置：禁用 telephony feed
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 添加 PassWall feeds
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

if [ ! -d "feeds/passwall2" ]; then
    echo "❌ passwall2 feed failed to download"
    exit 1
fi

# 清理问题包
PROBLEM_PKGS="aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl python-rpds-py python-service-identity python-twisted python-docker python-jsonschema python-jsonschema-specifications python-referencing onionshare-cli onionshare weston wpewebkit libextractor python-bcrypt python-cryptography python-maturin podman ruby-yaml"

for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
rm -rf feeds/video feeds/telephony
rm -rf package/feeds

./scripts/feeds update -i || { echo "❌ feeds update -i failed"; exit 1; }
./scripts/feeds install -a || { echo "❌ feeds install failed"; exit 1; }

for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
./scripts/feeds update -i || { echo "❌ feeds update -i failed"; exit 1; }
make package/symlinks || { echo "❌ make package/symlinks failed"; exit 1; }

# ========== 注入设备定义 ==========
mkdir -p "$DTS_PATH_OLD" "$DTS_PATH_NEW"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_PATH_OLD/"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_PATH_NEW/"

cat >> "$FILOGIC_MK" << 'EOF'

# SL3000 设备定义（自动注入）
define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981b-sl3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    luci-app-passwall2 \
    xray-core chinadns-ng \
    shadowsocks-libev-ss-local shadowsocks-libev-ss-redir shadowsocks-libev-ss-tunnel \
    shadowsocks-rust-sslocal simple-obfs \
    docker-ce docker-compose kmod-br-netfilter kmod-ikconfig kmod-ipt-physdev \
    kmod-nf-ipt6 kmod-nf-ipvs kmod-veth kmod-fs-overlay luci-app-dockerman
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF

grep -q "sl_3000-emmc" "$FILOGIC_MK" || { echo "❌ 设备定义未写入"; exit 1; }

# ========== 生成基础配置 ==========
cp "$CONFIG_DIR/sl3000.config" .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

make defconfig || { echo "❌ make defconfig failed"; exit 1; }
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

make -j1 V=s oldconfig 2>&1 | tee oldconfig.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ oldconfig 失败"
    tail -50 oldconfig.log
    exit 1
fi

grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config || {
    echo "❌ 设备未在 .config 中启用"
    exit 1
}
echo "✅ 设备已启用"

# 保存构建目录路径供 part2 使用
echo "$PWD" > "$WORKSPACE/build-dir.txt"
