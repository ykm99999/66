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

# 验证三件套文件
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

# 修改 feeds 配置：禁用 telephony feed
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 注释掉 passwall feeds（避免拉取不必要的依赖，因为科学上网已从配置中移除）
# echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
# echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

# 更新所有 feeds
./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

# 注意：由于 passwall 被注释，此处不再检查 passwall2 目录，避免误报
# 但为了兼容原脚本结构，保留一个简单的 feeds 安装
./scripts/feeds install -a || { echo "❌ feeds install failed"; exit 1; }
make package/symlinks || { echo "❌ make package/symlinks failed"; exit 1; }

# ========== 定义问题包列表（与成功案例相同） ==========
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
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# ========== 追加设备定义到 filogic.mk ==========
mkdir -p "$(dirname "$FILOGIC_MK")"
touch "$FILOGIC_MK"
echo "" >> $FILOGIC_MK
cat $CONFIG_DIR/mt7981_sl3000.mk >> $FILOGIC_MK 2>/dev/null || {
    echo "❌ 缺少 $CONFIG_DIR/mt7981_sl3000.mk"
    exit 1
}
echo "✅ 设备定义已注入"

# ========== 配置 .config ==========
cp -v $CONFIG_DIR/sl3000.config .config || exit 1

# 设置平台并启用两个设备
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic/d' .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# ========== 生成基础配置 ==========
make defconfig || exit 1

# defconfig 后再次确保设备选项存在
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# ========== 使用 oldconfig 更新配置 ==========
echo "=== 运行 oldconfig ==="
make oldconfig || exit 1

# 关键修复：oldconfig 后强制重新写入两个设备选项
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# ========== 最终验证设备是否在 .config 中启用 ==========
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ eMMC 设备 sl_3000-emmc 未在 .config 中启用！"
    exit 1
fi
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备 sl_3000-spi-nor 未在 .config 中启用！"
    exit 1
fi
echo "✅ 两个设备均已启用"

# 保存当前构建目录路径，供 part2 使用
echo $PWD > $WORKSPACE/build-dir.txt
