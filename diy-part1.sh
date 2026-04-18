#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"

cd "$IMMORTAL_DIR"

echo "=== 1. 底层物理手术：强行修改默认架构 ==="
# 修复：直接修改 OpenWrt 的默认配置文件，将默认值从 x86 改为 mediatek
# 这样即便配置解析出错，它默认也是进入 mediatek 分支，绝不跳 x86
sed -i 's/CONFIG_TARGET_x86=y/# CONFIG_TARGET_x86 is not set/' Config-build.in
sed -i 's/default "x86"/default "mediatek"/' config/Config-build.in 2>/dev/null || true

echo "=== 2. 底层物理注入：将 SL3000 设备定义写入底层 Makefile ==="
# 如果底层 filogic.mk 缺少定义，我们直接物理追加
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
if ! grep -q "sl_3000-emmc" "$FILOGIC_MK"; then
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

echo "=== 3. Feeds 物理同步 ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo "✅ 底层仓库源物理加固完成。"
