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

sed -i 's/^src-git telephony/#src-git telephony/' feeds.conf.default

./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

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

# ========== 6. 补全内核 config-6.6 中的缺失选项 ==========
echo "=== 补全内核缺失选项 ==="
KERNEL_CFG="target/linux/mediatek/filogic/config-6.6"
if [ -f "$KERNEL_CFG" ]; then
    # 追加所有可能缺失的选项（默认值）
    cat <<'KCFG_APPEND' >> "$KERNEL_CFG"

# Added by diy-part1.sh to fix syncconfig issues
CONFIG_BFQ_GROUP_IOSCHED=y
CONFIG_UCLAMP_TASK=n
CONFIG_RODATA_FULL_DEFAULT_ENABLED=y
CONFIG_UNMAP_KERNEL_AT_EL0=y
CONFIG_MITIGATE_SPECTRE_BRANCH_HISTORY=y
CONFIG_HZ_100=y
# CONFIG_HZ_250 is not set
# CONFIG_HZ_300 is not set
# CONFIG_HZ_1000 is not set
# CONFIG_NUMA is not set
# CONFIG_SCHED_CLUSTER is not set
# CONFIG_SCHED_SMT is not set
KCFG_APPEND

    # 重新运行 oldconfig 以使内核配置更新
    make -j1 V=s oldconfig 2>&1 | tail -20
    echo "✅ 内核配置补丁已应用"
else
    echo "❌ 未找到 $KERNEL_CFG"
    exit 1
fi

echo "$PWD" > "$WORKSPACE/build-dir.txt"
