#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

# 物理溯源：直接抓取编译器的绝对路径，彻底根治 Error 127
GCC_PATH=$(which aarch64-linux-gnu-gcc)
if [ -z "$GCC_PATH" ]; then
    echo "❌ 物理环境中未发现 aarch64-linux-gnu-gcc"
    exit 1
fi
# 提取前缀 (例如 /usr/bin/aarch64-linux-gnu-)
CROSS_PREFIX="${GCC_PATH%gcc}"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)

# ========== 1. ATF 补丁 (原文照抄，printf 注入) ==========
cd "$SOURCE_DIR/arm-trusted-firmware"
mkdir -p plat/mediatek/mt7981/drivers/dram

printf "/* Forced DDR4 */\n#include <plat/common/platform.h>\n#include <common/debug.h>\n#include <lib/mmio.h>\nextern void mtk_mem_init_real(void);\nextern int mt7981_use_ddr4;\nvoid mtk_mem_init(void) {\n    mt7981_use_ddr4 = 1;\n    NOTICE(\"EMI: Forced DDR4 for SL3000\\\\n\");\n    mtk_mem_init_real();\n}\nvoid mtk_mem_dbg_print(const char *fmt, ...) {}\nvoid mtk_mem_err_print(const char *fmt, ...) {}\n" > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c

# ========== 2. 编译 ATF (强制注入绝对路径) ==========
echo "=== Building ATF (1GB DDR4 EMMC) ==="
make clean
# 在 make 指令中直接绑定物理路径
make CROSS_COMPILE="$CROSS_PREFIX" PLAT=mt7981 DEBUG=0 \
     BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1

mkdir -p "$OUTPUT_DIR/atf"
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin"

# ========== 3. 编译 U-Boot (强制注入绝对路径) ==========
cd "$SOURCE_DIR/u-boot"
make clean
make CROSS_COMPILE="$CROSS_PREFIX" mt7981_emmc_rfb_defconfig
make CROSS_COMPILE="$CROSS_PREFIX" -j$(nproc)

mkdir -p "$OUTPUT_DIR/uboot"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 4. 编译固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s

mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f -name "*sysupgrade*" -exec cp {} "$OUTPUT_DIR/firmware/" \;
echo "✅ SL3000 全链路复刻成功"
