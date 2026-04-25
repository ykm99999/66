#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"          # 包含 immortalwrt/ ATF/ U-Boot/ mtk_uartboot/
CONFIG_DIR="$WORKSPACE/main-repo/888"       # 三件套 + files 所在目录
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"

rm -rf "$IMMORTALWRT_BUILD" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 验证三件套文件 ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981b-sl3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000.config"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/mt7981_sl3000.mk" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981_sl3000.mk"
    exit 1
fi
echo "✅ 三件套完整"

# ========== 2. 准备 ImmortalWrt 源码 ==========
cp -r "$SOURCE_DIR/immortalwrt" "$IMMORTALWRT_BUILD"
cd "$IMMORTALWRT_BUILD"

# 禁用 telephony feed（可选）
sed -i 's/^src-git telephony/#src-git telephony/' feeds.conf.default

# 注意：不再添加 passwall 相关 feeds

./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

# 清理问题包（可选，不影响科学/Docker）
PROBLEM_PKGS="aardvark-dns clamav podman ruby-yaml"
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

# 复制设备树（使用真实文件名）
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_PATH_OLD/"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_PATH_NEW/"

# ========== 4. 注入设备 mk 定义（直接追加到 filogic.mk，不再包含科学/Docker） ==========
echo "" >> "$FILOGIC_MK"
cat "$CONFIG_DIR/mt7981_sl3000.mk" >> "$FILOGIC_MK"
echo "✅ 设备定义已注入 filogic.mk"

# 检查设备名是否出现（用于确认）
if ! grep -q "sl.3000" "$FILOGIC_MK"; then
    echo "⚠️ 设备名 'sl_3000-emmc' 未在 filogic.mk 中找到，请检查 mt7981_sl3000.mk 内容"
fi

# ========== 5. 复制自定义 files（关键：将你的修改打入固件） ==========
if [ -d "$CONFIG_DIR/files" ]; then
    echo "=== 注入自定义 files ==="
    cp -rv "$CONFIG_DIR/files" "$IMMORTALWRT_BUILD/"
    echo "✅ 自定义 files 已复制"
else
    echo "⚠️ 未发现自定义 files 目录，跳过"
fi

# ========== 6. 配置 OpenWrt ==========
cp -v "$CONFIG_DIR/sl3000.config" .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

make defconfig

# 运行 oldconfig 使配置生效
make -j1 V=s oldconfig 2>&1 | tee oldconfig.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ oldconfig 失败："
    tail -50 oldconfig.log
    exit 1
fi

# 再次确保设备选项已启用
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
    make olddefconfig
fi

# 保存编译目录路径
echo "$PWD" > "$WORKSPACE/build-dir.txt"
