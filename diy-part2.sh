#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
# 假设内核文件位于编译输出目录
BIN_DIR="$WORKSPACE/openwrt/bin/targets/mediatek/mt7981"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

# ---------- 使用从原厂32.bin提取的引导文件 ----------
echo "=== 使用原厂提取的引导文件 ==="
cp -v "$MAIN_REPO/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$MAIN_REPO/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$MAIN_REPO/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

# ---------- 修复：定位并获取构建的内核文件 ----------
# 寻找编译生成的 ITB 镜像（包含 Kernel 和 DTS）
KERNEL_FILE=$(find "$BIN_DIR" -name "*sl_3000-emmc-sysupgrade.itb" | head -n 1)

if [ -f "$KERNEL_FILE" ]; then
    echo "=== 发现构建内核: $(basename "$KERNEL_FILE") ==="
    cp -v "$KERNEL_FILE" "$PARTS_DIR/kernel.itb"
else
    echo "❌ 错误：未找到构建的内核文件 (*.itb)，请检查编译流程。"
    exit 1
fi

# ---------- 合成 32MB 救砖镜像 ----------
echo "=== 合成 rescue-32.bin (2 版) ==="
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 创建 32MB 空文件，全部填充 0xFF
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 1. 写入 BL2（偏移 0x0）
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none

# 2. 写入 FIP（偏移 0x40000 = 256KB）
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none

# 3. 写入 Factory（偏移 0x180000 = 1.5MB）
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none

# 4. 写入 Kernel/ITB（偏移 0x200000 = 2MB）
# 这是修复的核心：将构建好的内核放入镜像中
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ 2 版救砖镜像已生成（含内核）: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"
