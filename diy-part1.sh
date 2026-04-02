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

# 准备 ImmortalWrt 源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 注册设备树
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# 追加设备定义到 filogic.mk
echo "" >> $FILOGIC_MK
cat $CONFIG_DIR/mt7981_sl3000.mk >> $FILOGIC_MK
if ! grep -q "sl_3000-spi-nor" $FILOGIC_MK; then
    echo "❌ 设备定义未成功写入"
    exit 1
fi
echo "✅ 设备定义已注入"

# 复制基础配置
cp -v $CONFIG_DIR/sl3000.config .config || exit 1

# 强制写入平台和设备（使用 sed 删除旧配置并添加新配置）
sed -i '/CONFIG_TARGET_mediatek=y/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic=y/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor/d' .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 禁用有问题的 luci 应用（避免依赖警告）
for pkg in clamav dufs openclash rustdesk-server smartdns; do
    sed -i "/CONFIG_PACKAGE_luci-app-${pkg}/d" .config
    echo "# CONFIG_PACKAGE_luci-app-${pkg} is not set" >> .config
done

# 生成基础配置
make defconfig || exit 1

# defconfig 后再次强制写入（因为 defconfig 可能重置）
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 运行 oldconfig
make oldconfig || exit 1

# oldconfig 后再次强制写入
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 最终验证
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ eMMC 设备未启用！"
    exit 1
fi
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 两个设备均已启用"

# 保存构建目录
echo $PWD > $WORKSPACE/build-dir.txt
