#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK_DIR="target/linux/mediatek/image"

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
if [ ! -f "$CONFIG_DIR/mt7981_sl3000.mk" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981_sl3000.mk"
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

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 删除可能导致编译错误的包（只删除必要且影响大的）
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

# 删除 mt76 无线驱动包（救砖不需要）
if [ -d package/kernel/mt76 ]; then
    rm -rf package/kernel/mt76
    echo "✅ 已删除 mt76"
fi

# 注册设备树（只复制到正确的新路径）
mkdir -p $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts $DTS_PATH_NEW/ || exit 1
echo "✅ 设备树已复制到 $DTS_PATH_NEW"

# 处理设备定义文件：复制 mt7981_sl3000.mk
mkdir -p $FILOGIC_MK_DIR
cp -v $CONFIG_DIR/mt7981_sl3000.mk $FILOGIC_MK_DIR/ || exit 1
echo "✅ 设备定义文件已复制"

# 复制救砖配置
cp -v $CONFIG_DIR/sl3000-rescue.config .config || exit 1

# 强制设置平台，只启用救砖设备（使用追加方式，避免重复）
cat >> .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y
EOF

# 生成配置
make defconfig || exit 1
# 确保目标设备未被意外覆盖
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 救砖设备已启用"

# 保存构建目录
echo $PWD > $WORKSPACE/build-dir.txt
