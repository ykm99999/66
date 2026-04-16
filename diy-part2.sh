#!/bin/bash
set -euo pipefail

# 物理修复：终端环境锁定
export TERM=xterm-256color

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"
IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 强制修改 ATF 源码 (原文照抄) ==========
echo "=== Patching ATF source to force DDR4 ==="
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram

cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>

extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
void mtk_mem_init(void) {
	mt7981_use_ddr4 = 1;
	NOTICE("EMI: Using DDR4 settings forced\n");
	mtk_mem_init_real();
}
EOF

# ========== 编译 ATF/U-Boot/固件 (原文照抄) ==========
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-emmc.bin

cd $SOURCE_DIR/u-boot
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s
find bin/targets/ -type f \( -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
