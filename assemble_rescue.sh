#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 检查并准备引导文件 ==="

# BL2
if [ -f "$CONFIG_DIR/bl2_orig.bin" ]; then
    cp -v "$CONFIG_DIR/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
else
    echo "❌ 缺少 bl2_orig.bin，无法合成"
    exit 1
fi

# FIP
if [ -f "$CONFIG_DIR/fip_orig.bin" ]; then
    cp -v "$CONFIG_DIR/fip_orig.bin" "$PARTS_DIR/fip.bin"
else
    echo "❌ 缺少 fip_orig.bin，无法合成"
    exit 1
fi

# Factory (如果没有则创建 2MB 空白占位)
if [ -f "$CONFIG_DIR/factory_orig.bin" ]; then
    cp -v "$CONFIG_DIR/factory_orig.bin" "$PARTS_DIR/factory.bin"
else
    echo "⚠️ 未找到 factory_orig.bin，创建 2MB 空白占位文件"
    dd if=/dev/zero bs=2M count=1 2>/dev/null | tr '\000' '\377' > "$PARTS_DIR/factory.bin"
fi

echo "=== 合成 Spi-flash-32MB-rescue.bin (原厂偏移) ==="
RESCUE_BIN="$OUTPUT_DIR/Spi-flash-32MB-rescue.bin"

# 创建 32MB 空文件，全部填充 0xFF
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# BL2 @ 0x0
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
echo "  BL2 written at 0x0"

# Factory @ 0x180000 (seek=6 for 256KB blocks)
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
echo "  Factory written at 0x180000"

# FIP @ 0x380000 (seek=14 for 256KB blocks)
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=14 conv=notrunc status=none
echo "  FIP written at 0x380000"

echo "✅ 救砖镜像已生成: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"

echo "=========================================="
echo "✅ 构建完成，输出目录内容："
ls -la "$OUTPUT_DIR"
echo "=========================================="
