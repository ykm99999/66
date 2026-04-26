#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/main-repo"
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

# 禁用可能出问题的 feed
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

# 追加设备 mk 定义
echo "" >> "$FILOGIC_MK"
cat "$CONFIG_DIR/mt7981_sl3000.mk" >> "$FILOGIC_MK"

# 提取真实设备名（eg: mt7981_sl3000_spi_rescue）
DEVICE_NAME=$(grep -oP 'TARGET_DEVICES\s*\+=\s*\K\S+' "$FILOGIC_MK" | tail -1)
if [ -z "$DEVICE_NAME" ]; then
    echo "❌ 无法提取设备名"
    exit 1
fi
echo "✅ 设备名: $DEVICE_NAME"

# ========== 4. 复制自定义 files（preinit/shadow/network/99-auto-firstboot） ==========
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

# 二次确保设备选项已启用
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y" .config; then
    echo "CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_NAME}=y" >> .config
fi

# ========== 6. 修复内核 NVMEM 依赖（写入内核配置片段，避免交互式错误） ==========
echo "=== 修复内核 NVMEM 依赖 ==="
KERNEL_CONFIG="target/linux/mediatek/filogic/config-6.6"
if [ -f "$KERNEL_CONFIG" ]; then
    if ! grep -q "CONFIG_NVMEM=y" "$KERNEL_CONFIG"; then
        echo "CONFIG_NVMEM=y" >> "$KERNEL_CONFIG"
    fi
    echo "✅ 已添加 CONFIG_NVMEM=y 到 $KERNEL_CONFIG"
else
    echo "⚠️ 未找到 $KERNEL_CONFIG，跳过内核配置修复"
fi

# 保存编译目录路径供 diy-part2.sh 使用
echo "$PWD" > "$WORKSPACE/build-dir.txt"
