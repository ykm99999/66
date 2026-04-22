#!/bin/bash
set -e

ROOT_DIR=$(pwd)
INPUT_DIR="$ROOT_DIR/output"
OUTPUT_IMAGE="$INPUT_DIR/rescue-32M.bin"
VERSION_FILE="$INPUT_DIR/version.txt"
RELEASE_NOTES="$INPUT_DIR/release_notes.md"

IMAGE_SIZE=$((32 * 1024 * 1024))

echo "Creating empty 32MB image filled with 0xFF..."
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$OUTPUT_IMAGE"

echo "Writing BL2 at offset 0x0..."
dd if="$INPUT_DIR/bl2-emmc-ddr4.bin" of="$OUTPUT_IMAGE" bs=1K seek=0 conv=notrunc 2>/dev/null

echo "Writing FIP (primary) at offset 0x100000 (1M)..."
dd if="$INPUT_DIR/bl31-uboot-emmc-ddr4.fip" of="$OUTPUT_IMAGE" bs=1K seek=1024 conv=notrunc 2>/dev/null

echo "Writing FIP (backup) at offset 0x200000 (2M)..."
dd if="$INPUT_DIR/bl31-uboot-emmc-ddr4.fip" of="$OUTPUT_IMAGE" bs=1K seek=2048 conv=notrunc 2>/dev/null

echo "Writing Kernel (sysupgrade.itb) at offset 0x300000 (3M)..."
dd if="$INPUT_DIR/sysupgrade.itb" of="$OUTPUT_IMAGE" bs=1K seek=3072 conv=notrunc 2>/dev/null

ACTUAL_SIZE=$(stat -c%s "$OUTPUT_IMAGE")
echo "Rescue image created: $OUTPUT_IMAGE ($ACTUAL_SIZE bytes)"

if [ $ACTUAL_SIZE -ne $IMAGE_SIZE ]; then
    echo "Warning: Expected size $IMAGE_SIZE bytes, got $ACTUAL_SIZE bytes"
fi

md5sum "$OUTPUT_IMAGE" > "$OUTPUT_IMAGE.md5"
echo "Checksum saved to $OUTPUT_IMAGE.md5"

# ---------- 生成版本信息 ----------
echo "Generating version info..."
{
    echo "Build Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Git Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    echo "Git Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    echo "Image Size:  $ACTUAL_SIZE bytes (32 MiB)"
    echo "Components:"
    echo "  BL2:        $(du -h "$INPUT_DIR/bl2-emmc-ddr4.bin" | cut -f1)"
    echo "  FIP:        $(du -h "$INPUT_DIR/bl31-uboot-emmc-ddr4.fip" | cut -f1)"
    echo "  Kernel:     $(du -h "$INPUT_DIR/sysupgrade.itb" | cut -f1)"
} > "$VERSION_FILE"

# ---------- 生成 Release Notes ----------
{
    echo "## SL3000 Rescue Firm
