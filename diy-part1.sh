#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"

cd "$IMMORTAL_DIR"

echo "=== 1. 底层物理手术：架构自愈锁定 ==="
# 物理溯源：寻找 Config-build.in 的真实路径
CONFIG_IN=$(find . -name "Config-build.in" | head -n 1)

if [ -n "$CONFIG_IN" ]; then
    echo "发现底层文件: $CONFIG_IN，开始物理注入..."
    # 物理抹除 x86 默认标识，强行将 mediatek 注入为默认首选
    sed -i 's/default "x86"/default "mediatek"/' "$CONFIG_IN" 2>/dev/null || true
    sed -i 's/CONFIG_TARGET_x86=y/# CONFIG_TARGET_x86 is not set/' "$CONFIG_IN" 2>/dev/null || true
else
    echo "⚠️ 警告：未发现 Config-build.in，跳过静默注入"
fi

echo "=== 2. 设备定义修复：filogic.mk 物理补丁 ==="
# 锁定 MT7981 设备的物理定义文件
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

if [ -f "$FILOGIC_MK" ]; then
    if ! grep -q "sl_3000-emmc" "$FILOGIC_MK"; then
        echo "正在底层 Makefile 中注册 SL3000 设备..."
        cat <<EOF >> "$FILOGIC_MK"

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC
  DEVICE_DTS := mt7981b-sl-3000-emmc
  DEVICE_DRAM_SIZE := 1024M
  SUPPORTED_DEVICES := sl,3000-emmc
endef
TARGET_DEVICES += sl_3000-emmc
EOF
    fi
else
    echo "❌ 严重错误：未发现底层设备定义文件 $FILOGIC_MK"
    exit 1
fi

echo "=== 3. Feeds 物理同步 ==="
# 确保脚本具备执行权限并同步
chmod +x scripts/feeds
./scripts/feeds update -a
./scripts/feeds install -a

echo "✅ [Part 1] 底层手术完成，物理链路已闭合。"
