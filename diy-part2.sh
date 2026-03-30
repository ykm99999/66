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

# ========== 强制修改 ATF 源码，启用 DDR4 ==========
echo "=== Patching ATF source to force DDR4 ==="
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram

# 禁用 EOF，使用 printf 逐行精确还原你贴出的源码逻辑
printf '/*\n * Copyright (c) 2021, MediaTek Inc. All rights reserved.\n *\n * SPDX-License-Identifier: BSD-3-Clause\n */\n\n' > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#include <plat/common/platform.h>\n#include <common/debug.h>\n#include <lib/mmio.h>\n#include <stdarg.h>\n#include <stdio.h>\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '/* IAP/REBB eFuse bit */\n#define IAP_REBB_SWITCH\t\t0x11D00A0C\n#define IAP_IND\t\t\t0x01\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'extern void mtk_mem_init_real(void);\nextern int mt7981_use_ddr4;\nextern int mt7981_ddr_size_limit;\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'extern int mt7981_dram_debug;\nextern int mt7981_bga_pkg;\nextern int mt7981_ddr3_freq;\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'void mtk_mem_init(void)\n{\n\t/* 强制使用 DDR4 */\n\tmt7981_use_ddr4 = 1;\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#ifdef DRAM_SIZE_LIMIT\n\tmt7981_ddr_size_limit = DRAM_SIZE_LIMIT;\n\n\tif (!mt7981_use_ddr4 && mt7981_ddr_size_limit > 512)\n\t\tmt7981_ddr_size_limit = 512;\n#endif /* DRAM_SIZE_LIMIT */\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#ifdef DRAM_DEBUG_LOG\n\tmt7981_dram_debug = 1;\n#endif /* DRAM_DEBUG_LOG */\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#if defined(BOARD_BGA)\n\tmt7981_bga_pkg = 1;\n#elif defined(BOARD_QFN)\n\tmt7981_bga_pkg = 0;\n#endif /* BOARD_BGA */\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '#ifdef DDR3_FREQ_2133\n\tmt7981_ddr3_freq = 2133;\n#endif\n#ifdef DDR3_FREQ_1866\n\tmt7981_ddr3_freq = 1866;\n#endif\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf '\tNOTICE("EMI: Using DDR%%u settings\\n", mt7981_use_ddr4 ? 4 : 3);\n\n\tmtk_mem_init_real();\n}\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'void mtk_mem_dbg_print(const char *fmt, ...)\n{\n\tva_list args;\n\tif (!mt7981_dram_debug)\n\t\treturn;\n\tva_start(args, fmt);\n\t(void)vprintf(fmt, args);\n\tva_end(args);\n}\n\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
printf 'void mtk_mem_err_print(const char *fmt, ...)\n{\n\tconst char *prefix_str;\n\tva_list args;\n\tprefix_str = plat_log_get_prefix(LOG_LEVEL_ERROR);\n\twhile (*prefix_str != \'\\0\') {\n\t\t(void)putchar(*prefix_str);\n\t\tprefix_str++;\n\t}\n\tva_start(args, fmt);\n\t(void)vprintf(fmt, args);\n\tva_end(args);\n}\n' >> plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c
echo "✅ ATF source patched for DDR4"

# ========== 编译 ATF (严格延续原版顺序) ==========
echo "=== Building ATF 512M (EMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 512M emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 512M emmc"

if command -v strings &> /dev/null; then
    if strings build/mt7981/release/bl2.bin | grep -qi "DDR4"; then
        echo "✅ 512M BL2 is DDR4"
    else
        echo "❌ 512M BL2 is NOT DDR4, check patching!"
        exit 1
    fi
fi

echo "=== Building ATF 1G (EMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 1G emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 1G emmc"

if command -v strings &> /dev/null; then
    if strings build/mt7981/release/bl2.bin | grep -qi "DDR4"; then
        echo "✅ 1G BL2 is DDR4"
    else
        echo "❌ 1G BL2 is NOT DDR4, check patching!"
        exit 1
    fi
fi

# 新增 256M NOR
echo "=== Building ATF 256M (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=256 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-256m-nor.bin \; 2>/dev/null

# 新增 512M NOR
echo "=== Building ATF 512M (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-nor.bin \; 2>/dev/null

echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

echo "=== Building ATF RAM (1G DDR4) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.bin \; 2>/dev/null || echo "No bl2.bin for RAM"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.elf \; 2>/dev/null || echo "No bl2.elf for RAM"

if [ ! -f "$OUTPUT_DIR/atf/bl2-ram-1g.bin" ]; then
    echo "❌ bl2-ram-1g.bin not generated! Check ATF compilation for RAM."
    exit 1
else
    echo "✅ bl2-ram-1g.bin generated successfully"
fi

if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found after ATF compilation!"
    exit 1
fi

cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" || { echo "❌ Failed to copy bl31.bin for emmc"; exit 1; }
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" || { echo "❌ Failed to copy bl31.bin for nor"; exit 1; }

ls -la "$STAGING_DIR_IMAGE"/mt7981-*.bin || { echo "❌ Copied bl31 files missing"; exit 1; }

echo "=== Compiling fiptool from ATF ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ========== 编译 U-Boot (eMMC版) 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
echo "=== Building U-Boot (eMMC) ==="
make clean
if [ -f configs/mt7981_emmc_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
else
    echo "❌ mt7981_emmc_rfb_defconfig not found!"
    exit 1
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    echo "⚠️ fip.bin not generated for eMMC, creating manually..."
    if [ -f "$FIPTOOL" ]; then
        if [ ! -f "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" ]; then
            echo "❌ mt7981-emmc-ddr4-bl31.bin not found!"
            exit 1
        fi
        "$FIPTOOL" create \
            --soc-fw "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" \
            --nt-fw u-boot.bin \
            u-boot.fip
        cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin"
    else
        echo "❌ fiptool not found, cannot create FIP"
        exit 1
    fi
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-emmc.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin" 2>/dev/null
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 编译 U-Boot (NOR版) 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
echo "=== Building U-Boot (NOR) ==="
make clean
if [ -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
else
    echo "❌ mt7981_spim_nor_rfb_defconfig not found, cannot build NOR U-Boot"
    exit 1
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    echo "⚠️ fip.bin not generated for NOR, creating manually..."
    if [ -f "$FIPTOOL" ]; then
        if [ ! -f "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" ]; then
            echo "❌ mt7981-nor-ddr4-bl31.bin not found!"
            exit 1
        fi
        "$FIPTOOL" create \
            --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" \
            --nt-fw u-boot.bin \
            u-boot.fip
        cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
    else
        echo "❌ fiptool not found, cannot create FIP"
        exit 1
    fi
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 编译 ImmortalWrt 完整固件 ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ Device sl_3000-emmc not enabled in .config!"
    exit 1
fi

make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed! Last 100 lines of build.log:"
    tail -100 build
