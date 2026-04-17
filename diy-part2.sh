#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"
mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 强制修改 ATF 源码，启用 DDR4 (物理复刻，禁用 EOF) ==========
echo "=== Patching ATF source to force DDR4 ==="
cd "$SOURCE_DIR/arm-trusted-firmware"
mkdir -p plat/mediatek/mt7981/drivers/dram

# 使用 printf 替代 cat <<EOF
printf "/*\n * Copyright (c) 2021, MediaTek Inc. All rights reserved.\n *\n * SPDX-License-Identifier: BSD-3-Clause\n */\n\n#include <plat/common/platform.h>\n#include <common/debug.h>\n#include <lib/mmio.h>\n#include <stdarg.h>\n#include <stdio.h>\n\n#define IAP_REBB_SWITCH 0x11D00A0C\n#define IAP_IND 0x01\n\nextern void mtk_mem_init_real(void);\nextern int mt7981_use_ddr4;\nextern int mt7981_ddr_size_limit;\nextern int mt7981_dram_debug;\nextern int mt7981_bga_pkg;\nextern int mt7981_ddr3_freq;\n\nvoid mtk_mem_init(void)\n{\n    mt7981_use_ddr4 = 1;\n#ifdef DRAM_SIZE_LIMIT\n    mt7981_ddr_size_limit = DRAM_SIZE_LIMIT;\n    if (!mt7981_use_ddr4 && mt7981_ddr_size_limit > 512)\n        mt7981_ddr_size_limit = 512;\n#endif\n#ifdef DRAM_DEBUG_LOG\n    mt7981_dram_debug = 1;\n#endif\n#if defined(BOARD_BGA)\n    mt7981_bga_pkg = 1;\n#elif defined(BOARD_QFN)\n    mt7981_bga_pkg = 0;\n#endif\n#ifdef DDR3_FREQ_2133\n    mt7981_ddr3_freq = 2133;\n#endif\n#ifdef DDR3_FREQ_1866\n    mt7981_ddr3_freq = 1866;\n#endif\n    NOTICE(\"EMI: Using DDR%%u settings\\\\n\", mt7981_use_ddr4 ? 4 : 3);\n    mtk_mem_init_real();\n}\n\nvoid mtk_mem_dbg_print(const char *fmt, ...)\n{\n    va_list args;\n    if (!mt7981_dram_debug) return;\n    va_start(args, fmt);\n    (void)vprintf(fmt, args);\n    va_end(args);\n}\n\nvoid mtk_mem_err_print(const char *fmt, ...)\n{\n    const char *prefix_str;\n    va_list args;\n    prefix_str = plat_log_get_prefix(LOG_LEVEL_ERROR);\n    while (*prefix_str != '\\\\0') {\n        (void)putchar(*prefix_str);\n        prefix_str++;\n    }\n    va_start(args, fmt);\n    (void)vprintf(fmt, args);\n    va_end(args);\n}\n" > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c

echo "✅ ATF source patched for DDR4"

# ========== 2. 编译多版本 ATF (原文参数复刻) ==========
echo "=== Building ATF Versions ==="

# 512M EMMC
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-512m-emmc.bin"
cp build/mt7981/release/bl2.elf "$OUTPUT_DIR/atf/bl2-512m-emmc.elf"

# 1G EMMC
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp build/mt7981/release/bl2.elf "$OUTPUT_DIR/atf/bl2-1g-emmc.elf"
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin"

# 1G NOR (Recovery)
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# 1G RAM (UART Boot)
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-ram-1g.bin"

# 编译 fiptool
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ========== 3. 编译 U-Boot (EMMC/NOR) ==========
cd "$SOURCE_DIR/u-boot"

# EMMC 版
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" --nt-fw u-boot.bin u-boot.fip
cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# NOR 版 (物理对齐配置名)
make clean
if [ -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
else
    # 物理回退至确认存在的 nor_emmc 配置
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_nor_emmc_rfb_defconfig
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" --nt-fw u-boot.bin u-boot.fip
cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 4. 编译 ImmortalWrt 固件 ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ Device sl_3000-emmc not enabled!"
    exit 1
fi

make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" -j$(nproc) V=s 2>&1 | tee build.log || exit 1

find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

# ========== 5. 打包 mtk_uartboot ==========
cd "$SOURCE_DIR/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ diy-part2.sh 执行完毕"
