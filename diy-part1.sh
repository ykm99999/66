#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.12/arch/arm64/boot/dts/mediatek"
MK_FILE="target/linux/mediatek/image/mt7981_sl3000.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证三件套文件是否存在 ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981_sl3000.mk" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981_sl3000.mk"
    exit 1
fi
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
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置：禁用 telephony feed（在 update 之前执行）
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 更新 feeds
./scripts/feeds update -a

# ========== 定义问题包列表（此处是需要经常修改的部分）==========
PROBLEM_PKGS="
aardvark-dns
arp-whisper
bottom
cargo-c
clamav
dufs
eza
fish
lsd
netavark
pdns-recursor
procs
python-setuptools-rust
ripgrep
ruby
rust-bindgen
rustdesk-server
shadow-tls
shadowsocks-rust
shadowsocks-rust-sslocal
shadowsocks-rust-ssserver
spotifyd
tuic-client
tuic-server
yggdrasil-jumper
gst1-plugins-base
gst1-plugins-good
gst1-plugins-ugly
libdmapsharing
kamailio
smartdns
pymysql
python-orjson
python-paramiko
python-pyopenssl
python-rpds-py
python-service-identity
python-twisted
python-docker
python-jsonschema
python-referencing
onionshare-cli
onionshare
weston
wpewebkit
luci-app-passwall
luci-app-rustdesk-server
luci-app-spotifyd
luci-app-clamav
luci-app-dufs
luci-app-openclash
luci-app-smartdns
libextractor
python-bcrypt
python-cryptography
python-maturin
podman
ruby-yaml
"

# ========== 彻底清除所有已知问题包 ==========
echo "=== 递归删除所有问题包 ==="
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 删除整个 video 和 telephony feed（确保删除）
rm -rf feeds/video feeds/telephony

# 清理 package/feeds 下的符号链接
rm -rf package/feeds

# 更新 feed 索引
./scripts/feeds update -i

# 安装 feeds（此时问题包已不存在）
./scripts/feeds install -a

# 再次递归删除（防止某些包因依赖被重新拉取）
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 再次更新索引并重建符号链接
./scripts/feeds update -i
make package/symlinks

# ========== 注册三件套 ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1
cp -v $CONFIG_DIR/mt7981_sl3000.mk $MK_FILE || exit 1

if ! grep -q "sl_3000-emmc" $MK_FILE; then
    echo "❌ 设备定义未成功写入 $MK_FILE"
    exit 1
fi

cp -v $CONFIG_DIR/sl3000.config .config || exit 1
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

# ========== 生成基础配置 ==========
make defconfig

# 再次写入设备选项（defconfig 可能会重置）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
make olddefconfig

# 验证设备是否在 .config 中启用
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ 设备 sl_3000-emmc 未在 .config 中启用！"
    exit 1
fi
echo "✅ 设备已启用"

# 保存当前构建目录路径，供 part2 使用
echo $PWD > $WORKSPACE/build-dir.txt
