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
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>

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
	mt7981_use_ddr4 = 1;
#ifdef DRAM_SIZE_LIMIT
	mt7981_ddr_size_limit = DRAM_SIZE_LIMIT;
	if (!mt7981_use_ddr4 && mt7981_ddr_size_limit > 512)
		mt7981_ddr_size_limit = 512;
#endif
#ifdef DRAM_DEBUG_LOG
	mt7981_dram_debug = 1;
#endif
#if defined(BOARD_BGA)
	mt7981_bga_pkg = 1;
#elif defined(BOARD_QFN)
	mt7981_bga_pkg = 0;
#endif
#ifdef DDR3_FREQ_2133
	mt7981_ddr3_freq = 2133;
#endif
#ifdef DDR3_FREQ_1866
	mt7981_ddr3_freq = 1866;
#endif
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

# ========== 编译 ATF (像素级复刻) ==========
echo "=== Building ATF 512M/1G/RAM ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-512m-emmc.bin || true

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-emmc.bin || true

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin || true

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-ram-1g.bin || true
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin"
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# ========== 编译 U-Boot (原文照抄) ==========
echo "=== Building U-Boot FIP ==="
make -C "$SOURCE_DIR/arm-trusted-firmware/tools/fiptool"
FIPTOOL="$SOURCE_DIR/arm-trusted-firmware/tools/fiptool/fiptool"

cd $SOURCE_DIR/u-boot
make clean && make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" --nt-fw u-boot.bin "$OUTPUT_DIR/uboot/fip-emmc.bin"

make clean && make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" --nt-fw u-boot.bin "$OUTPUT_DIR/uboot/fip-nor.bin"

# ========== 编译 ImmortalWrt (原文照抄) ==========
cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s

# ========== 最小物理修补：修复产物提取与缝合逻辑 ==========
mkdir -p "$OUTPUT_DIR/firmware"
# 修正提取路径：确保能找到编译出的 sysupgrade.bin
find bin/targets/mediatek/filogic/ -name "*sysupgrade.bin" -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

echo "=== Creating 32MB Spi-flash-32MB.bin ==="
cd "$OUTPUT_DIR/firmware"
dd if=/dev/zero bs=1k count=32768 | tr '\000' '\377' > Spi-flash-32MB.bin
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of=Spi-flash-32MB.bin conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of=Spi-flash-32MB.bin bs=1k seek=3584 conv=notrunc

# 寻找刚才提取到 firmware 目录下的固件进行缝合
SYSUPGRADE_FILE=$(ls *sysupgrade.bin | head -n 1)
if [ -n "$SYSUPGRADE_FILE" ]; then
    dd if="$SYSUPGRADE_FILE" of=Spi-flash-32MB.bin bs=1k seek=4096 conv=notrunc
    echo "✅ Spi-flash-32MB.bin created at $OUTPUT_DIR/firmware/"
else
    echo "❌ ERROR: No sysupgrade.bin found for stitching!"
    exit 1
fi

# ========== 最终验证 ==========
ls -lh "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
