#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理环境强控：环境变量注入 ==="
export TERM=xterm
export M4=$(which m4)

echo "=== 2. 注入配置与静默校验 ==="
cd "$IMMORTAL_DIR"

# 物理覆盖核心配置
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    cp -f "$WORKSPACE/888/sl3000.config" .config
    echo "✅ 注入 sl3000.config"
else
    echo "❌ 关键错误：找不到 $WORKSPACE/888/sl3000.config"
    exit 1
fi

# 彻底解决 Error opening terminal: unknown
make defconfig

echo "=== 3. 强制编译内核 ITB ==="
# 物理诊断：V=s 暴露所有细节，j1 确保在工具链不稳定时也能成功
make target/linux/compile -j$(nproc) V=s

echo "=== 4. 镜像物理合成 (dd) ==="
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)

if [ -z "$KERNEL_SRC" ] || [ ! -f "$KERNEL_SRC" ]; then
    echo "❌ 审计失败：未在 bin/ 目录下发现 ITB 文件"
    exit 1
fi

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 生成 32MB 全 0xFF 底图
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 严格偏移量写入 (物理对齐)
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [全链路诊断成功] 救砖包已合成: $RESCUE_BIN"
