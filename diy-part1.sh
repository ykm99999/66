#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/main-repo"           # 源码都在 main-repo 下
CONFIG_DIR="$SOURCE_DIR/888"
OUTPUT_DIR="$SOURCE_DIR/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"

rm -rf "$IMMORTALWRT_BUILD" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware" "$OUTPUT_DIR/rescue"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 验证三件套 ==========
echo "=== 验证配置文件 ==="
for f in mt7981b-sl3000-emmc.dts sl3000.config mt7981_sl3000.mk; do
    if [ ! -f "$CONFIG_DIR/$f" ]; then
        echo "❌ 缺少 $CONFIG_DIR/$f"
        exit 1
    fi
done
echo "✅ 三件套完整"

# ========== 2. 准备 ImmortalWrt 源码 ==========
cp -r "$SOURCE_DIR/immortalwrt" "$IMMORTALWRT_BUILD"
cd "$IMMORTALWRT_BUILD"

sed -i 's/^src-git telephony/#src-git telephony/' feeds.conf.default

./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

# 删除已知问题包（无科学/Docker）
PROBLEM_PKGS="aardvark-dns clamav luci-app-clamav podman ruby-yaml"
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
rm -rf feeds/video feeds/telephony
rm -rf package/feeds
./scripts/feeds update -i
./scripts/feeds install -a || { echo "❌ feeds install failed"; exit 1; }

# ========== 3. 注入设备树（双路径） ==========
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p "$DTS_PATH_OLD" "$DTS_PATH_NEW"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_PATH_OLD/"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_PATH_NEW/"

echo "" >> "$FILOGIC_MK"
cat "$CONFIG_DIR/mt7981_sl3000.mk" >> "$FILOGIC_MK"

# 提取真实设备名
DEVICE_NAME=$(grep -oP 'TARGET_DEVICES\s*\+=\s*\K\S+' "$FILOGIC_MK" | tail -1)
if [ -z "$DEVICE_NAME" ]; then
    echo "❌ 无法提取设备名"
    exit 1
fi
echo "✅ 设备名: $DEVICE_NAME"

# ========== 4. 复制自定义 files ==========
if [ -d "$CONFIG_DIR/files" ]; then
    echo "=== 注入自定义 files ==="
    cp -rv "$CONFIG_DIR/files" "$IMMORTALWRT_BUILD/"
    echo "✅ 自定义 files 已复制"
else
    echo "⚠️ 未发现自定义 files 目录"
fi

# ========== 5. 配置 OpenWrt ==========
cp -v "$CONFIG_DIR/sl3000.config" .config
{
    echo "CONFIG_TARGET_mediatek=y"
    echo "CONFIG_TARGET_mediatek_filogic=y"
    echo "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y"
} >> .config

make defconfig
make -j1 V=s oldconfig 2>&1 | tee oldconfig.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ oldconfig 失败"
    tail -50 oldconfig.log
    exit 1
fi

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y" .config; then
    echo "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y" >> .config
fi

# ========== 6. 自动生成完整内核配置（终极解决） ==========
echo "=== 自动补全内核配置（消除所有交互） ==="
make target/linux/prepare V=s 2>&1 | tail -20

# 定位内核构建目录
KERNEL_DIR=$(find build_dir -maxdepth 5 -name "linux-6.6*" -type d | head -1)
if [ -z "$KERNEL_DIR" ]; then
    echo "❌ 未找到内核目录"
    exit 1
fi

cd "$KERNEL_DIR"
cp ../../../../target/linux/mediatek/filogic/config-6.6 .config
make ARCH=arm64 olddefconfig 2>&1
cd "$IMMORTALWRT_BUILD"
cp -f "$KERNEL_DIR/.config" target/linux/mediatek/filogic/config-6.6
echo "✅ 内核配置已更新为完整版本"

cd "$IMMORTALWRT_BUILD"
echo "$PWD" > "$WORKSPACE/build-dir.txt"
