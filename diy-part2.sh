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
    echo "  BL2:        $(du -h "$INPUT_DIR/bl2-emmc-ddr4.bin" 2>/dev/null | cut -f1 || echo 'missing')"
    echo "  FIP:        $(du -h "$INPUT_DIR/bl31-uboot-emmc-ddr4.fip" 2>/dev/null | cut -f1 || echo 'missing')"
    echo "  Kernel:     $(du -h "$INPUT_DIR/sysupgrade.itb" 2>/dev/null | cut -f1 || echo 'missing')"
} > "$VERSION_FILE"

# ---------- 生成 Release Notes ----------
cat > "$RELEASE_NOTES" << EOF
## SL3000 Rescue Firmware (32MB)

### Build Information
- **Date:** $(date '+%Y-%m-%d %H:%M:%S')
- **Git Commit:** $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')
- **Branch:** $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')

### Flashing Instructions
1. Use **mtk_uartboot** to load BL2 and FIP via UART.
2. Then flash the combined \`rescue-32M.bin\` using U-Boot:
   \`\`\`
   mmc dev 0
   mmc write \$loadaddr 0x0 0x10000
   \`\`\`
   Or use \`mmc part\` and \`mmc write\` for specific partitions.

### Partition Layout
| Offset | Size | Component |
|--------|------|-----------|
| 0x000000 | 1M | BL2 (Preloader) |
| 0x100000 | 1M | FIP (ATF+U-Boot) |
| 0x200000 | 1M | FIP Backup |
| 0x300000 | ~29M | Kernel (sysupgrade.itb) |

### Included Files
- \`rescue-32M.bin\` – Full 32MB image
- \`rescue-32M.bin.md5\` – MD5 checksum
- \`bl2-emmc-ddr4.bin\` – Standalone BL2
- \`bl31-uboot-emmc-ddr4.fip\` – Standalone FIP
- \`sysupgrade.itb\` – Kernel image

### Notes
- This build is automatically generated via GitHub Actions.
- Ensure your device matches the SL3000 hardware configuration.
EOF

echo "Release notes generated."
