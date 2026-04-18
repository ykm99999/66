#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
# 镜像内物理偏移量定义
OFFSET_FIP=256    # 256KB = 1 * 256k seek
OFFSET_FACT=1536  # 1.5MB = 6 * 256k seek
OFFSET_KERN=2048  # 2MB   = 2 * 1M seek

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理环境核对 ==="
[ -d "$IMMORTAL_DIR" ] || { echo "❌ 缺少源码目录: $IMMORTAL_DIR"; exit 1; }
[ -d "$WORKSPACE/888" ] || { echo "❌ 缺少 888 引导资源目录"; exit 1; }

echo "=== 2. 强制启动内核构建 ==="
cd "$IMMORTAL_DIR"
# 确保环境已同步
./scripts/feeds update -a && ./scripts/feeds install -a
# 强制使用 sl3000 配置
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    cp -f "$WORKSPACE/888/sl3000.config" .config
    make defconfig
fi

# 仅编译内核 ITB，这是最稳健的物理生成方式
echo "开始编译 target/linux/compile..."
make target/linux/compile -j$(nproc) V=s

echo "=== 3. 提取并校验产物 ==="
# 物理路径锁定
KERNEL_SRC=$(find "$IMMORTAL_DIR/bin/targets" -name "*sysupgrade.itb" | head -n 1)

if [ -z "$KERNEL_SRC" ] || [ ! -f "$KERNEL_SRC" ]; then
    echo "❌ 严重错误：内核 ITB 文件未生成，请检查编译日志。"
    exit 1
fi
cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
cp -v "$WORKSPACE/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$WORKSPACE/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$WORKSPACE/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

echo "=== 4. 物理合成 32MB 救砖镜像 ==="
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 创建 32MB 擦除态底图 (0xFF)
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 顺序写入 (严格遵循 Flash 布局)
echo "写入引导与配置分区..."
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none

echo "写入内核 ITB (Offset: 2MB)..."
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [彻底修复] 完整救砖全家桶已生成！"
ls -lh "$RESCUE_BIN"
