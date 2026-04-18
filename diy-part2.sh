#!/bin/bash
set -euo pipefail

# 1. 路径自适应
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理审计：源码与资源检查 ==="
[ -d "$IMMORTAL_DIR" ] || { echo "❌ 缺少 immortalwrt 目录"; exit 1; }
[ -d "$WORKSPACE/888" ] || { echo "❌ 缺少 888 引导文件目录"; exit 1; }

echo "=== 2. 修复编译环境并构建内核 ==="
cd "$IMMORTAL_DIR"

# 解决 flex/m4 报错：清理并强制执行配置生成
make target/linux/clean
./scripts/feeds update -a && ./scripts/feeds install -a

if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    echo "注入 sl3000.config 配置文件..."
    cp -f "$WORKSPACE/888/sl3000.config" .config
    make defconfig
fi

echo "正在执行内核编译 (target/linux/compile)..."
# 使用 V=s 暴露所有物理错误，防止静默失败
make target/linux/compile -j$(nproc) V=s

echo "=== 3. 提取内核产物与引导文件 ==="
# 物理路径锁定
KERNEL_SRC=$(find bin/targets/mediatek/mt7981 -name "*sysupgrade.itb" | head -n 1)

if [ -z "$KERNEL_SRC" ] || [ ! -f "$KERNEL_SRC" ]; then
    echo "❌ 物理审计失败：未能在编译输出中找到内核 ITB 文件。"
    exit 1
fi

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
cp -v "$WORKSPACE/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$WORKSPACE/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$WORKSPACE/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

echo "=== 4. 物理合成 32MB 救砖镜像 ==="
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 创建 32MB 全 0xFF 空镜像（模拟物理擦除状态）
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 按偏移量物理写入
echo "写入 BL2 (Offset: 0)..."
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none

echo "写入 FIP (Offset: 256KB)..."
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none

echo "写入 Factory (Offset: 1.5MB)..."
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none

echo "写入 Kernel ITB (Offset: 2MB)..."
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [彻底解决] 32MB 全量救砖镜像已生成！"
ls -lh "$RESCUE_BIN"
