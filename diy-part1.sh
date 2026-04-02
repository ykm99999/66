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
if [ ! -f "$CONFIG_DIR/sl3000-mini.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000-mini.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# 准备 ImmortalWrt 源码
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置（禁用 telephony，移除 passwall）
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
sed -i '/passwall/d' feeds.conf.default

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

# 复制极简配置
cp -v $CONFIG_DIR/sl3000-mini.config .config || exit 1

# 强制启用平台和救砖设备，禁用 eMMC
./scripts/config --enable CONFIG_TARGET_mediatek
./scripts/config --enable CONFIG_TARGET_mediatek_filogic
./scripts/config --enable CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor
./scripts/config --disable CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc

# 确保所有无线、科学上网、Docker 相关配置被禁用（极简配置已无，但防御）
./scripts/config --disable CONFIG_PACKAGE_kmod-mt7915e
./scripts/config --disable CONFIG_PACKAGE_kmod-mt76
./scripts/config --disable CONFIG_PACKAGE_xray-core
./scripts/config --disable CONFIG_PACKAGE_docker-ce
./scripts/config --disable CONFIG_PACKAGE_luci-app-passwall2

# 生成基础配置
make defconfig || exit 1

# 再次确保设备启用（defconfig 可能重置）
./scripts/config --enable CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor
./scripts/config --disable CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc

# 运行 oldconfig
make oldconfig || exit 1

# 最后强制确保
./scripts/config --enable CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor

# 验证
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 救砖设备已启用"

# 保存构建目录
echo $PWD > $WORKSPACE/build-dir.txt
