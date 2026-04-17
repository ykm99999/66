#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

# 物理修复：强制指定交叉编译器前缀
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$STAGING_DIR_IMAGE" "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)

# ========== 1. ATF 补丁 (禁用 EOF) ==========
cd "$SOURCE_DIR/arm-trusted-firmware"
mkdir -p plat/mediatek/mt7981/drivers/dram

printf "#include <plat/common/platform.h>\n#include <common/debug.h>\n#include <lib/mmio.h>\n#include <stdarg.h>\n#include <stdio.h>\nextern void mtk_mem_init_real(void);\nextern int mt7981_use_ddr4;\nvoid mtk_mem_init(void) {\n    mt7981_use_ddr4 = 1;\n    NOTICE(\"EMI: Forced DDR4 for SL3000\\\\n\");\n    mtk_mem_init_real();\n}\nvoid mtk_mem_dbg_print(const char *fmt, ...) {}\nvoid mtk_mem_err_print(const char *fmt, ...) {}\n" > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c

# ========== 2. 编译 ATF (修复编译器找不到) ==========
echo "=== Building ATF Versions ==="

# 强制在执行 make 时传入编译器环境变量
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 \
     BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1

cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin"

# ========== 3. 编译 U-Boot ==========
cd "$SOURCE_DIR/u-boot"
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 4. 编译固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s

find bin/targets/ -type f -name "*sysupgrade*" -exec cp {} "$OUTPUT_DIR/firmware/" \;
echo "✅ 编译流程完成"
