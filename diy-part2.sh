#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理环境自愈：构建 Host 工具链 ==="
cd "$IMMORTAL_DIR"
# 预构建必要工具，确保路径无误
make tools/install -j$(nproc)

echo "=== 2. 物理粉碎架构冲突 (解决卡死核心) ==="
# 修复：先彻底清理 .config，防止旧的 x86 配置残留
rm -f .config
touch .config

# 强制注入 SL3000 (1G DDR4) 物理架构锁定
# 这几行必须在最前面，且后面要剔除冲突项
cat <<EOF > .config
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_mt7981=y
CONFIG_TARGET_mediatek_mt7981_DEVICE_sl_3000-emmc=y
EOF

# 步骤 B: 处理你的 8000 行配置，物理剔除所有 x86 相关干扰项
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    echo "正在清洗并合并 8000 行核心配置..."
    # 物理过滤：剔除所有其他的 TARGET 架构定义，防止冲突
    grep -v "CONFIG_TARGET_" "$WORKSPACE/888/sl3000.config" >> .config
    echo "✅ 核心配置已清洗合并"
else
    echo "❌ 找不到 sl3000.config"; exit 1
fi

# 步骤 C: 强制静默对齐
# 使用 --defconfig 强制按我们设定的架构重置全图
make defconfig

echo "=== 3. 执行内核构建 (1024M 规格) ==="
# 此时配置已物理锁定在 mediatek，绝不会跳回 x86
make target/linux/compile -j$(nproc) V=s

echo "=== 4. 救砖镜像物理合成 (32MB) ==="
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)
[ -z "$KERNEL_SRC" ] && { echo "❌ 审计失败：内核 ITB 未生成"; exit 1; }

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 物理合成逻辑 (0xFF 填充模拟 SPI Flash)
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [彻底解决] 架构已强行对齐，救砖包合成成功。"
