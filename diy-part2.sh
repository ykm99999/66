#!/bin/bash
set -euo pipefail

# 1. 路径自适应：确定当前物理工作空间
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
if [ -d "$WORKSPACE/main-repo" ]; then
    ROOT_DIR="$WORKSPACE/main-repo"
else
    ROOT_DIR="$WORKSPACE"
fi

OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"
mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 提取引导与工厂分区数据 ==="
# 修复：路径直接指向 888 目录
cp -v "$ROOT_DIR/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$ROOT_DIR/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$ROOT_DIR/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

echo "=== 2. 搜索构建产物 (内核 ITB) ==="
# 修复：物理搜索路径扩充，确保能找到 immortalwrt 编译出的产物
# 优先搜索 immortalwrt 的输出目录，如果没有则全局搜索
KERNEL_SRC=$(find "$WORKSPACE/immortalwrt/bin/targets/mediatek/mt7981" -name "*sl_3000-emmc-sysupgrade.itb" 2>/dev/null | head -n 1)

if [ -z "$KERNEL_SRC" ]; then
    KERNEL_SRC=$(find "$WORKSPACE" -name "*sl_3000-emmc-sysupgrade.itb" 2>/dev/null | head -n 1)
fi

if [ -n "$KERNEL_SRC" ] && [ -f "$KERNEL_SRC" ]; then
    echo "✅ 找到内核文件: $KERNEL_SRC"
    cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
else
    echo "❌ 错误：未找到内核 .itb 文件，合成中止。请检查编译日志是否成功生成了固件。"
    exit 1
fi

echo "=== 3. 开始合成 32MB 救砖镜像 (rescue-32.bin) ==="
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 创建 32MB 填充文件 (0xFF)
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 物理位置写入 (严格对齐偏移量)
# BL2 (0x0)
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
# FIP (256KB)
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
# Factory (1.5MB)
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
# Kernel (2MB) - 修复：确保内核被写入
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ 救砖镜像合成成功: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"
