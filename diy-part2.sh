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

# 修复缺失的头文件路径
mkdir -p include/drivers/mediatek

# 1. 处理 emi.h（软链接）
if [ -f plat/mediatek/mt7981/drivers/dram/emi.h ]; then
    ln -sf ../../../plat/mediatek/mt7981/drivers/dram/emi.h include/drivers/mediatek/emi.h
    echo "✅ 已创建 emi.h 软链接"
else
    echo "❌ 未找到 emi.h"
    exit 1
fi

# 2. 处理 emicfg.h（如果不存在则创建占位，并修改 emicfg.c 的 include）
if [ -f plat/mediatek/mt7981/drivers/dram/emicfg.h ]; then
    cp plat/mediatek/mt7981/drivers/dram/emicfg.h include/drivers/mediatek/
    echo "✅ 已复制 emicfg.h 到 include 路径"
else
    echo "⚠️ emicfg.h 不存在，创建占位文件"
    cat > include/drivers/mediatek/emicfg.h << 'EOF'
#ifndef EMICFG_H
#define EMICFG_H

#include <stdint.h>

/* Placeholder for emicfg.h */
void emicfg_init(void);

#endif /* EMICFG_H */
EOF
fi

# 修改 emicfg.c 中的 include 语句
if [ -f plat/mediatek/mt7981/drivers/dram/emicfg.c ]; then
    sed -i 's/#include "emicfg.h"/#include <drivers\/mediatek\/emicfg.h>/' plat/mediatek/mt7981/drivers/dram/emicfg.c
    echo "✅ 已修复 emicfg.c 中的头文件引用"
else
    echo "❌ 未找到 emicfg.c"
    exit 1
fi

# 3. 创建 mtk_mem_init.c 补丁（强制 DDR4）
mkdir -p plat/mediatek/mt7981/drivers/dram
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
/*
 * Copyright (c) 2021, MediaTek Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>

/* IAP/REBB eFuse bit */
#define IAP_REBB_SWITCH		0x11D00A0C
#define IAP_IND			0x01

extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
extern int mt7981_ddr_size_limit;
extern int mt7981_dram_debug;
extern int mt7981_bga_pkg;
extern int mt7981_ddr3_freq;

void mtk_mem_init(void)
{
	/* 强制使用 DDR4 */
	mt7981_use_ddr4 = 1;

#ifdef DRAM_SIZE_LIMIT
	mt7981_ddr_size_limit = DRAM_SIZE_LIMIT;

	if (!mt7981_use_ddr4 && mt7981_ddr_size_limit > 512)
		mt7981_ddr_size_limit = 512;
#endif /* DRAM_SIZE_LIMIT */

#ifdef DRAM_DEBUG_LOG
	mt7981_dram_debug = 1;
#endif /* DRAM_DEBUG_LOG */

#if defined(BOARD_BGA)
	mt7981_bga_pkg = 1;
#elif defined(BOARD_QFN)
	mt7981_bga_pkg = 0;
#endif /* BOARD_BGA */

#ifdef DDR3_FREQ_2133
	mt7981_ddr3_freq = 2133;
#endif /* DDR3_FREQ_2133 */
#ifdef DDR3_FREQ_1866
	mt7981_ddr3_freq = 1866;
#endif /* DDR3_FREQ_1866 */

	NOTICE("EMI: Using DDR%u settings\n", mt7981_use_ddr4 ? 4 : 3);

	mtk_mem_init_real();
}

void mtk_mem_dbg_print(const char *fmt, ...)
{
	va_list args;

	if (!mt7981_dram_debug)
		return;

	va_start(args, fmt);
	(void)vprintf(fmt, args);
	va_end(args);
}

void mtk_mem_err_print(const char *fmt, ...)
{
	const char *prefix_str;
	va_list args;

	prefix_str = plat_log_get_prefix(LOG_LEVEL_ERROR);

	while (*prefix_str != '\0') {
		(void)putchar(*prefix_str);
		prefix_str++;
	}

	va_start(args, fmt);
	(void)vprintf(fmt, args);
	va_end(args);
}
EOF
echo "✅ ATF source patched for DDR4"

# ========== 编译 ATF（只编译 NOR 和 RAM 版） ==========
echo "=== Building ATF 1G (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

echo "=== Building ATF RAM (1G) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.bin \; 2>/dev/null || echo "No bl2.bin for RAM"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.elf \; 2>/dev/null || echo "No bl2.elf for RAM"

if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found"
    exit 1
fi
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# ========== 编译 fiptool ==========
echo "=== Compiling fiptool ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"
mkdir -p $SOURCE_DIR/u-boot/tools
cp -f $FIPTOOL $SOURCE_DIR/u-boot/tools/fiptool

# ========== 编译 U-Boot (NOR版) ==========
cd $SOURCE_DIR/u-boot
make clean
if [ -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
else
    echo "❌ mt7981_spim_nor_rfb_defconfig not found"
    exit 1
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    $FIPTOOL create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" --nt-fw u-boot.bin u-boot.fip
    cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 构建 SPI-NOR 救砖固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ Rescue device not enabled"
    exit 1
fi

make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
cp build.log "$OUTPUT_DIR/firmware/"

SPI_IMAGE=$(find bin/targets/ -type f -name '*sl_3000-spi-nor*sysupgrade.bin' -size -34M | head -1)
if [ -z "$SPI_IMAGE" ]; then
    echo "❌ No SPI-NOR rescue image found"
    exit 1
fi
cp "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
echo "✅ SPI-NOR rescue image saved as Spi-flash-32MB.bin"

# ========== 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ Build complete"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
