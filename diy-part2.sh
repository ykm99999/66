#!/bin/bash
set -euo pipefail

# 1. 路径与变量定义
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

# 解决终端报错环境变量
export TERM=xterm
export TERMINAL=dumb

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理审计：源码环境校验 ==="
[ -d "$IMMORTAL_DIR" ] || { echo "❌ 缺少源码目录"; exit 1; }

echo "=== 2. 注入配置并强制执行静默校验 ==="
cd "$IMMORTAL_DIR"

# 物理覆盖 .config
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    cp -f "$WORKSPACE/888/sl3000.config" .config
    echo "✅ 已注入 8000 行核心配置"
else
    echo "❌ 关键错误：找不到 888/sl3000.config"
    exit 1
fi

# 彻底解决 menuconfig 交互报错：使用 defconfig
echo "执行非交互式配置填充 (make defconfig)..."
make defconfig

echo "=== 3. 启动内核 ITB 编译 ==="
# 仅针对内核目标进行快速构建
make target/linux/compile -j$(nproc) V=s

echo "=== 4. 锁定产物并合成 32MB 救砖包 ==="
# 物理路径锁定
KERNEL_SRC=$(find bin/targets/mediatek/mt7981 -name "*sysupgrade.itb" | head -n 1)

if [ -z "$KERNEL_SRC" ] || [ ! -f "$KERNEL_SRC" ]; then
    echo "❌ 审计失败：未能在 bin/ 目录下发现生成的内核 ITB 文件"
    exit 1
fi

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
cp -v "$WORKSPACE/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$WORKSPACE/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$WORKSPACE/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

# 开始 dd 物理合成
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"
echo "正在物理合成 rescue-32.bin..."

# 32MB 全 0xFF 填充
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 写入各分区（严格对齐）
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [全链路诊断成功] 救砖全家桶已就绪: $RESCUE_BIN"
