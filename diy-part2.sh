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

# 使用 cat 写入文件（较短的版本，可保留 EOF，因为之前已证明可行）
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

echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

# 检查 bl31.bin 是否存在
if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found after ATF compilation!"
    exit 1
fi

# 复制 bl31.bin 到 staging_dir
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

# 在编译前验证设备是否在列表中
echo "=== Enabled mediatek/filogic devices ==="
make info | grep -A 30 "Target: mediatek/filogic" | grep "sl_3000" || { echo "❌ Device sl_3000-emmc not enabled!"; exit 1; }

make VERSION_NUMBER="1.0.0" VERSION_CODE="r1" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed! Last 100 lines of build.log:"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
cp build.log "$OUTPUT_DIR/firmware/"

# 检查是否有任何 .bin 文件生成
if [ ! -f "$OUTPUT_DIR/firmware/"*sysupgrade* ]; then
    echo "❌ No sysupgrade firmware files generated!"
    echo "Contents of bin/targets/ (first 50 files):"
    find bin/targets/ -type f | head -50
    echo "Last 100 lines of build.log:"
    tail -100 build.log
    exit 1
fi

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
