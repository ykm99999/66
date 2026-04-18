#!/bin/bash
set -euo pipefail

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
cp -v "$ROOT_DIR/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$ROOT_DIR/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$ROOT_DIR/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

echo "=== 2. 搜索构建产物 (内核 ITB) ==="
# 调试：打印出 bin 目录下所有的 itb 或 bin 文件，方便定位物理路径
echo "🔍 正在扫描编译输出目录..."
find "$WORKSPACE" -maxdepth 5 -name "*.itb" -o -name "*.bin" | grep -v "orig" || echo "⚠️ 未发现任何生成的镜像文件"

# 尝试多种可能的命名组合进行搜索
# 1. 尝试你定义的设备名
# 2. 尝试通用的 mt7981 sysupgrade 命名
KERNEL_SRC=$(find "$WORKSPACE" -name "*sl_3000-emmc-sysupgrade.itb" 2>/dev/null | head -n 1)

if [ -z "$KERNEL_SRC" ]; then
    echo "⚠️ 未找到精准匹配的 itb，尝试模糊搜索 mt7981 相关固件..."
    KERNEL_SRC=$(find "$WORKSPACE" -name "*mt7981*sysupgrade.itb" 2>/dev/null | head -n 1)
fi

if [ -n "$KERNEL_SRC" ] && [ -f "$KERNEL_SRC" ]; then
    echo "✅ 找到内核文件: $KERNEL_SRC"
    cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
else
    echo "❌ 错误：在工作空间中找不到任何符合条件的内核 ITB 文件。"
    echo "物理环境审计：当前目录内容如下："
    ls -R "$WORKSPACE/immortalwrt/bin/targets/" 2>/dev/null || echo "immortalwrt/bin 目录不存在"
    exit 1
fi

echo "=== 3. 开始合成 32MB 救砖镜像 (rescue-32.bin) ==="
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ 7 版救砖镜像合成成功: $RESCUE_BIN"
