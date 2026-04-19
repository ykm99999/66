#!/bin/bash
set -euo pipefail

# ==============================================
# SL3000 救砖全家桶合成脚本（无需编译，仅打包）
# 使用方法：将 bl2_orig.bin, fip_orig.bin, factory_orig.bin 放入 888/ 目录
#          运行此脚本，生成 output/Spi-flash-32MB-rescue.bin
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

ROOT_DIR=$(pwd)
CONFIG_DIR="$ROOT_DIR/888"
OUTPUT_DIR="$ROOT_DIR/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

# ---------- 检查必需文件 ----------
log_step "检查原厂引导文件..."
missing=0
for file in bl2_orig.bin fip_orig.bin factory_orig.bin; do
    if [ ! -f "$CONFIG_DIR/$file" ]; then
        log_error "缺失文件: $CONFIG_DIR/$file"
        missing=1
    fi
done
if [ $missing -eq 1 ]; then
    log_error "请将 bl2_orig.bin, fip_orig.bin, factory_orig.bin 放入 888/ 目录"
    exit 1
fi
log_info "所有必需文件已就绪"

# ---------- 复制文件到工作目录 ----------
log_step "准备分区文件..."
cp -v "$CONFIG_DIR/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$CONFIG_DIR/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$CONFIG_DIR/factory_orig.bin" "$PARTS_DIR/factory.bin"

# ---------- 合成 32MB 救砖镜像 ----------
log_step "合成 Spi-flash-32MB-rescue.bin (严格遵循原厂偏移)..."
RESCUE_BIN="$OUTPUT_DIR/Spi-flash-32MB-rescue.bin"

# 创建 32MB 空文件，全部填充 0xFF（Flash 擦除态）
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 1. BL2 @ 0x0
dd if="$PARTS_DIR/bl2.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
echo "  -> BL2 written at 0x000000"

# 2. Factory @ 0x180000 (1.5 MB) = 256KB * 6
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
echo "  -> Factory written at 0x180000"

# 3. FIP @ 0x380000 (3.5 MB) = 256KB * 14
dd if="$PARTS_DIR/fip.bin" of="$RESCUE_BIN" bs=256k seek=14 conv=notrunc status=none
echo "  -> FIP written at 0x380000"

log_info "✅ 救砖镜像已生成: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"

# ---------- 输出校验信息 ----------
log_step "镜像前 64 字节预览 (BL2 头部):"
hexdump -C -n 64 "$RESCUE_BIN" | head -5

log_step "FIP 头部魔数校验 (偏移 0x380000):"
dd if="$RESCUE_BIN" bs=1 skip=$((0x380000)) count=16 2>/dev/null | hexdump -C

echo ""
log_info "🎉 救砖全家桶构建完成！"
echo "输出目录: $OUTPUT_DIR"
echo "烧录文件: $RESCUE_BIN"
