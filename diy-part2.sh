#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== ATF 补丁逻辑 (原文照抄) ==========
cd $SOURCE_DIR/arm-trusted-firmware
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>

extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
void mtk_mem_init(void) {
    mt7981_use_ddr4 = 1; // 1版修复：强制 1GB DDR4
    mtk_mem_init_real();
}
EOF

# ========== 编译 ATF & U-Boot (最小修补) ==========
make PLAT=mt7981 BOOT_DEVICE=nor DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-ddr4-bl31.bin"

cd $SOURCE_DIR/u-boot
make mt7981_spim_nor_rfb_defconfig
make -j$(nproc)
cp u-boot.bin $OUTPUT_DIR/uboot/fip-nor.bin

# ========== 1版物理合成：救砖全家桶 (全链路诊断) ==========
echo "=== 合成 SL3000_SPI_RESCUE_V1.bin ==="
RESCUE_BIN="$OUTPUT_DIR/firmware/SL3000_SPI_RESCUE_V1.bin"
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$RESCUE_BIN" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$RESCUE_BIN" seek=512 conv=notrunc
sed -i 's/bootdelay=[0-9]/bootdelay=9/g' "$RESCUE_BIN"

# ========== 编译固件 (原文复刻) ==========
cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
