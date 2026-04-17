#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

# ---------- 使用从原厂32.bin提取的引导文件 ----------
echo "=== 使用原厂提取的引导文件 ==="
cp -v "$MAIN_REPO/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$MAIN_REPO/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$MAIN_REPO/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

# ---------- 合成 32MB 救砖镜像 ----------
echo "=== 合成 rescue-32.bin ==="
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 创建 32MB 空文件，全部填充 0xFF
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 写入 BL2（偏移 0x0）
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
# 写入 FIP（偏移 0x40000 = 256KB）
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
# 写入 Factory（偏移 0x180000 = 1.5MB）
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none

echo "✅ 救砖镜像已生成: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"
