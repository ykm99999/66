#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 强制修改 ATF 源码 (禁用 EOF 并物理转义括号) ==========
echo "=== Patching ATF source to force DDR4 ==?"
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram

# 使用单引号保护 printf 内容，防止 Shell 解析括号
printf '/*\n * Copyright (c) 2021, MediaTek Inc. All rights reserved.\n *\n * SPDX-License-Identifier: BSD-3-Clause\n */\n\n' > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#include <plat/common/platform.h>\n#include <common/debug.h>\n#include <lib/mmio.h>\n#include <stdarg.h>\n#include <stdio.h>\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#define IAP_REBB_SWITCH\t\t0x11D00A0C\n#define IAP_IND\t\t\t0x01\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'extern void mtk_mem_init_real(void);\nextern int mt7981_use_ddr4;\nextern int mt7981_ddr_size_limit;\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'extern int mt7981_dram_debug;\nextern int mt7981_bga_pkg;\nextern int mt7981_ddr3_freq;\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'void mtk_mem_init(void)\n{\n\tmt7981_use_ddr4 = 1; /* 强制 DDR4 逻辑 */\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#ifdef DRAM_SIZE_LIMIT\n\tmt7981_ddr_size_limit = DRAM_SIZE_LIMIT;\n\tif (!mt7981_use_ddr4 && mt7981_ddr_size_limit > 512)\n\t\tmt7981_ddr_size_limit = 512;\n#endif\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#ifdef DRAM_DEBUG_LOG\n\tmt7981_dram_debug = 1;\n#endif\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#if defined(BOARD_BGA)\n\tmt7981_bga_pkg = 1;\n#elif defined(BOARD_QFN)\n\tmt7981_bga_pkg = 0;\n#endif\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '\tNOTICE("EMI: Using DDR%%u settings\\n", mt7981_use_ddr4 ? 4 : 3);\n\tmtk_mem_init_real();\n}\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'void mtk_mem_dbg_print(const char *fmt, ...)\n{\n\tva_list args;\n\tif (!mt7981_dram_debug) return;\n\tva_start(args, fmt);\n\t(void)vprintf(fmt, args);\n\tva_end(args);\n}\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'void mtk_mem_err_print(const char *fmt, ...)\n{\n\tva_list args;\n\tva_start(args, fmt);\n\t(void)vprintf(fmt, args);\n\tva_end(args);\n}\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c

echo "✅ ATF source patched without syntax error"

# ========== 编译 ATF (256M / 512M / 1G NOR 三版本) ==========

echo "=== Building ATF 256M (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=256 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-256m-nor.bin \; 2>/dev/null

echo "=== Building ATF 512M (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-nor.bin \; 2>/dev/null

echo "=== Building ATF 1G (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null

echo "=== Building ATF 1G (EMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.bin \; 2>/dev/null
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin"

echo "=== Building ATF RAM (1G DDR4) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.bin \; 2>/dev/null

# ========== 编译 U-Boot & FIP (延续 121 行逻辑) ==========
cd $SOURCE_DIR/u-boot
make -C ../arm-trusted-firmware/tools/fiptool CROSS_COMPILE=
FIPTOOL="$SOURCE_DIR/arm-trusted-firmware/tools/fiptool/fiptool"

echo "=== Generating FIP (eMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" --nt-fw u-boot.bin "$OUTPUT_DIR/uboot/fip-emmc.bin"

# ========== 编译 ImmortalWrt (延续 121 行逻辑) ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"
make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" -j$(nproc) V=s 2>&1 | tee build.log

mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

# ========== 打包 mtk_uartboot (原版逻辑收尾) ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ 3版脚本（修正版）执行完毕。已解决括号语法错误。"
