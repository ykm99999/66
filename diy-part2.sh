#!/bin/bash
set -euo pipefail

# 1. 变量定义
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理补救：强制构建 Host 工具链 ==="
cd "$IMMORTAL_DIR"

# 彻底修复：先编译 bison/flex/m4 的 host 版本，确保路径对齐
# 这是解决 "cannot open m4sugar.m4" 的唯一物理方法
make tools/install -j$(nproc) || make tools/install -j1 V=s

echo "=== 2. 注入 8000 行配置并执行静默校验 ==="
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    cp -f "$WORKSPACE/888/sl3000.config" .config
    # 彻底消除 Error opening terminal: unknown
    make defconfig
else
    echo "❌ 错误：找不到物理配置文件 888/sl3000.config"
    exit 1
fi

echo "=== 3. 物理构建内核 ITB ==="
# 此时 staging_dir/host 已经物理存在正确的 bison 资源
make target/linux/compile -j$(nproc) V=s

echo "=== 4. 锁定产物执行全链路合成 ==="
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)

if [ -z "$KERNEL_SRC" ] || [ ! -f "$KERNEL_SRC" ]; then
    echo "❌ 审计失败：未能在编译输出中定位内核文件"
    exit 1
fi

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 物理合成 32MB 救砖包 (0xFF 填充模拟物理 Flash)
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 物理位置精准写入 (SOP)
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [彻底解决] 全链路物理构建成功：$RESCUE_BIN"
