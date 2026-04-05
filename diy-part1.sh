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

# 验证配置文件
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

# 准备 ImmortalWrt 源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置：禁用 telephony feed
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 添加 PassWall 系列 feeds（官方新地址）
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

# 更新所有 feeds
./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

# 确保 passwall2 feed 被正确拉取
if [ ! -d "feeds/passwall2" ]; then
    echo "❌ passwall2 feed failed to download. Please check the repository URL."
    exit 1
else
    echo "✅ passwall2 feed successfully updated"
fi

# ========== 定义问题包列表（精简版） ==========
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

# ========== 彻底清除所有已知问题包 ==========
echo "=== 递归删除所有问题包 ==="
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 删除整个 video 和 telephony feed
rm -rf feeds/video feeds/telephony

# 清理 package/feeds 下的符号链接
rm -rf package/feeds

# 更新 feed 索引
./scripts/feeds update -i || { echo "❌ feeds update -i failed"; exit 1; }

# 安装 feeds
./scripts/feeds install -a || { echo "❌ feeds install failed"; exit 1; }

# 再次递归删除（防止依赖重新拉取）
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 再次更新索引并重建符号链接
./scripts/feeds update -i || { echo "❌ feeds update -i failed"; exit 1; }
make package/symlinks || { echo "❌ make package/symlinks failed"; exit 1; }

# ========== 注册设备树（双路径） ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# ========== 追加设备定义到 filogic.mk ==========
echo "" >> $FILOGIC_MK
echo "# SL3000 eMMC 设备定义（保留，但不启用）" >> $FILOGIC_MK
echo "define Device/sl_3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_VENDOR := SL" >> $FILOGIC_MK
echo "  DEVICE_MODEL := 3000 eMMC (1GB)" >> $FILOGIC_MK
echo "  DEVICE_DTS := mt7981b-sl3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> $FILOGIC_MK
echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_PACKAGES := \\" >> $FILOGIC_MK
echo "    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \\" >> $FILOGIC_MK
echo "    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \\" >> $FILOGIC_MK
echo "    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \\" >> $FILOGIC_MK
echo "    luci-app-passwall2 \\" >> $FILOGIC_MK
echo "    xray-core chinadns-ng \\" >> $FILOGIC_MK
echo "    shadowsocks-libev-ss-local shadowsocks-libev-ss-redir shadowsocks-libev-ss-tunnel \\" >> $FILOGIC_MK
echo "    shadowsocks-rust-sslocal simple-obfs \\" >> $FILOGIC_MK
echo "    docker-ce docker-compose kmod-br-netfilter kmod-ikconfig kmod-ipt-physdev \\" >> $FILOGIC_MK
echo "    kmod-nf-ipt6 kmod-nf-ipvs kmod-veth kmod-fs-overlay luci-app-dockerman" >> $FILOGIC_MK
echo "  IMAGES := sysupgrade.bin" >> $FILOGIC_MK
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> $FILOGIC_MK
echo "endef" >> $FILOGIC_MK
echo "TARGET_DEVICES += sl_3000-emmc" >> $FILOGIC_MK

echo "" >> $FILOGIC_MK
echo "# SL3000 SPI-NOR 救砖设备定义" >> $FILOGIC_MK
echo "define Device/sl_3000-spi-nor" >> $FILOGIC_MK
echo "  DEVICE_VENDOR := SL" >> $FILOGIC_MK
echo "  DEVICE_MODEL := 3000 SPI-NOR (32MB)" >> $FILOGIC_MK
echo "  DEVICE_DTS := mt7981b-sl3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> $FILOGIC_MK
echo "  SUPPORTED_DEVICES := sl,3000-spi-nor" >> $FILOGIC_MK
echo "  DEVICE_PACKAGES := \\" >> $FILOGIC_MK
echo "    kmod-usb3 kmod-usb-storage \\" >> $FILOGIC_MK
echo "    block-mount \\" >> $FILOGIC_MK
echo "    uboot-envtools \\" >> $FILOGIC_MK
echo "    ttyd" >> $FILOGIC_MK
echo "  IMAGES := sysupgrade.bin" >> $FILOGIC_MK
echo "  IMAGE_SIZE := 32768k" >> $FILOGIC_MK
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> $FILOGIC_MK
echo "endef" >> $FILOGIC_MK
echo "TARGET_DEVICES += sl_3000-spi-nor" >> $FILOGIC_MK

# 验证
if ! grep -q "sl_3000-spi-nor" $FILOGIC_MK; then
    echo "❌ 救砖设备定义未写入"
    exit 1
fi

# ========== 配置 .config ==========
cp -v $CONFIG_DIR/sl3000.config .config || exit 1

echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
# 只启用救砖设备
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

make defconfig || exit 1
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

make oldconfig || exit 1
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备未启用"
    exit 1
fi
echo "✅ 救砖设备已启用"

echo $PWD > $WORKSPACE/build-dir.txt
