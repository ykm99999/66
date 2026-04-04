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
if [ ! -f "$CONFIG_DIR/mt7981-sl-3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981-sl-3000-emmc.dts"
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

# 修改 feeds 配置：禁用 telephony feed，不添加 passwall
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 删除可能导致编译错误的包（不影响救砖）
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

# 注册设备树
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# 追加设备定义（只包含救砖设备）
mkdir -p "$(dirname "$FILOGIC_MK")"
touch "$FILOGIC_MK"
echo "" >> $FILOGIC_MK
cat $CONFIG_DIR/mt7981_sl3000.mk >> $FILOGIC_MK 2>/dev/null || {
    echo "❌ 缺少 $CONFIG_DIR/mt7981_sl3000.mk"
    exit 1
}
echo "✅ 设备定义已注入"

# 复制基础配置
cp -v $CONFIG_DIR/sl3000.config .config || exit 1

# 强制启用平台和救砖设备，禁用 eMMC
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic/d' .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config
echo "# CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc is not set" >> .config

# ========== 关键：强制禁用所有无线驱动 ==========
echo "=== 强制禁用无线驱动 ==="
./scripts/config --disable CONFIG_PACKAGE_kmod-mt7915e
./scripts/config --disable CONFIG_PACKAGE_kmod-mt7915-firmware
./scripts/config --disable CONFIG_PACKAGE_kmod-mt76
./scripts/config --disable CONFIG_PACKAGE_kmod-mt76-core
./scripts/config --disable CONFIG_PACKAGE_kmod-mt76-connac
# 如果 scripts/config 不可用，则使用 sed 直接修改 .config
sed -i '/CONFIG_PACKAGE_kmod-mt7915e/d' .config
sed -i '/CONFIG_PACKAGE_kmod-mt7915-firmware/d' .config
sed -i '/CONFIG_PACKAGE_kmod-mt76/d' .config
echo "# CONFIG_PACKAGE_kmod-mt7915e is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-mt7915-firmware is not set" >> .config
echo "# CONFIG_PACKAGE_kmod-mt76 is not set" >> .config

# 生成基础配置
make defconfig || exit 1

# defconfig 后再次确保救砖设备存在且无线禁用
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config
sed -i '/CONFIG_PACKAGE_kmod-mt7915e/d' .config
echo "# CONFIG_PACKAGE_kmod-mt7915e is not set" >> .config

# 运行 oldconfig
echo "=== 运行 oldconfig ==="
make oldconfig || exit 1

# oldconfig 后再次强制写入
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config
sed -i '/CONFIG_PACKAGE_kmod-mt7915e/d' .config
echo "# CONFIG_PACKAGE_kmod-mt7915e is not set" >> .config

# 最终验证
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 救砖设备已启用"

echo "=== 验证无线驱动已禁用 ==="
if grep -q "CONFIG_PACKAGE_kmod-mt7915e=y" .config; then
    echo "❌ 无线驱动仍被启用！"
    exit 1
fi
echo "✅ 无线驱动已禁用"

# 保存构建目录
echo $PWD > $WORKSPACE/build-dir.txt
