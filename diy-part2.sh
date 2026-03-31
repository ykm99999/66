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

# ========== 编译 ATF ==========
echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

# 验证 bl2 是否为 DDR4
if command -v strings &> /dev/null; then
    if strings build/mt7981/release/bl2.bin | grep -qi "DDR4"; then
        echo "✅ NOR BL2 is DDR4"
    else
        echo "❌ NOR BL2 is NOT DDR4, check patching!"
        exit 1
    fi
fi

# ========== 编译 RAM 版 BL2 (1G, DDR4) ==========
echo "=== Building ATF RAM (1G DDR4) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.bin \; 2>/dev/null || echo "No bl2.bin for RAM"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.elf \; 2>/dev/null || echo "No bl2.elf for RAM"

# 验证 RAM 版是否生成
if [ ! -f "$OUTPUT_DIR/atf/bl2-ram-1g.bin" ]; then
    echo "❌ bl2-ram-1g.bin not generated! Check ATF compilation for RAM."
    exit 1
else
    echo "✅ bl2-ram-1g.bin generated successfully"
fi

# 检查 bl31.bin 是否存在（所有 ATF 编译完成后会生成一个 bl31.bin）
if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found after ATF compilation!"
    exit 1
fi

# 复制 bl31.bin 到 staging_dir（用于后续 FIP 生成）
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" || { echo "❌ Failed to copy bl31.bin for nor"; exit 1; }

ls -la "$STAGING_DIR_IMAGE"/mt7981-*.bin || { echo "❌ Copied bl31 files missing"; exit 1; }

echo "=== Compiling fiptool from ATF ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

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

# ========== 构建 SPI-NOR 救砖固件 ==========
echo "=== Building SPI-NOR Rescue Firmware (Spi-flash-32MB.bin) ==="
cd "$IMMORTALWRT_BUILD_DIR"

# 确保 .config 已存在（由 diy-part1.sh 生成）
if [ ! -f .config ]; then
    echo "❌ .config not found in $IMMORTALWRT_BUILD_DIR"
    exit 1
fi

# 直接检查 .config 文件中设备是否启用（避免 make info 因警告失败）
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ Device sl_3000-spi-nor not enabled in .config!"
    exit 1
fi

# 构建指定设备
make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" \
    DEVICE="sl_3000-spi-nor" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed! Last 100 lines of build.log:"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"

# 查找生成的 SPI-NOR 镜像（通常包含 spi-nor 和 32M 字样）
SPI_IMAGE=$(find bin/targets/ -type f -name '*spi-nor*32M*.bin' -o -name '*spi-nor*32mb*.bin' | head -1)
if [ -z "$SPI_IMAGE" ]; then
    # 尝试查找任何 bin 文件（可能命名不同）
    SPI_IMAGE=$(find bin/targets/ -type f -name '*.bin' | grep -E 'spi-nor|nor' | head -1)
fi

if [ -z "$SPI_IMAGE" ]; then
    echo "❌ No SPI-NOR image found!"
    echo "Available images:"
    find bin/targets/ -type f -name '*.bin' | head -20
    exit 1
fi

cp -v "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
echo "✅ Spi-flash-32MB.bin generated and copied to $OUTPUT_DIR/firmware/"

# 保存构建日志
cp build.log "$OUTPUT_DIR/firmware/"

# ========== 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
if [ $? -ne 0 ] || [ ! -f "$OUTPUT_DIR/mtk_uartboot.tar.gz" ]; then
    echo "❌ Failed to package mtk_uartboot"
    exit 1
fi

# ========== 最终输出 ==========
echo "✅ Build complete. Output directory contents:"
ls -la "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"
echo "mtk_uartboot.tar.gz is in $OUTPUT_DIR"
