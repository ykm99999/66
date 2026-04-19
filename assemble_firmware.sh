#!/bin/bash
# assemble_firmware.sh - 使用 888/ 中的原始文件和 sysupgrade.itb 合成最终固件

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

CONFIG_DIR="./888"
OUTPUT_DIR="./output"

if [ ! -d "$CONFIG_DIR" ]; then
    log_error "未找到 888/ 目录"
    exit 1
fi

# 检查必需文件
BL2_SRC="$CONFIG_DIR/bl2_orig.bin"
FIP_SRC="$CONFIG_DIR/fip_orig.bin"
FACTORY_SRC="$CONFIG_DIR/factory_orig.bin"
KERNEL_SRC="$OUTPUT_DIR/sysupgrade.itb"

missing=0
for f in "$BL2_SRC" "$FIP_SRC" "$FACTORY_SRC" "$KERNEL_SRC"; do
    if [ ! -f "$f" ]; then
        log_error "缺失文件: $f"
        missing=1
    fi
done

if [ $missing -eq 1 ]; then
    echo ""
    echo "请确保："
    echo "  - 888/bl2_orig.bin       (存在)"
    echo "  - 888/fip_orig.bin       (存在)"
    echo "  - 888/factory_orig.bin   (存在)"
    echo "  - 已运行 ./build_kernel.sh 生成 output/sysupgrade.itb"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 复制并重命名（合成脚本内部使用统一名称）
cp "$BL2_SRC"      "$OUTPUT_DIR/bl2-emmc-ddr3.bin"
cp "$FIP_SRC"      "$OUTPUT_DIR/bl31-uboot-emmc-ddr3.fip"
cp "$FACTORY_SRC"  "$OUTPUT_DIR/factory_orig.bin"
# sysupgrade.itb 已在 output 中，无需复制

cd "$OUTPUT_DIR"
FINAL_BIN="sl3000-rescue-32mb.bin"

log_info "创建 32MB 空文件（全 0xFF）..."
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$FINAL_BIN"

log_info "写入 BL2 (偏移 0M)..."
dd if=bl2-emmc-ddr3.bin of="$FINAL_BIN" conv=notrunc status=none

log_info "写入 FIP (偏移 1M)..."
dd if=bl31-uboot-emmc-ddr3.fip of="$FINAL_BIN" bs=1M seek=1 conv=notrunc status=none

log_info "写入 Factory (偏移 2M)..."
dd if=factory_orig.bin of="$FINAL_BIN" bs=1M seek=2 conv=notrunc status=none

log_info "写入 Kernel (偏移 3M)..."
dd if=sysupgrade.itb of="$FINAL_BIN" bs=1M seek=3 conv=notrunc status=none

log_info "✅ 合成完成！输出文件: $OUTPUT_DIR/$FINAL_BIN"
log_info "大小: $(du -h "$FINAL_BIN" | cut -f1)"
