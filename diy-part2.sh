#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware" "$STAGING_DIR_IMAGE"

# 强制进入 ATF 源码目录
cd $SOURCE_DIR/arm-trusted-firmware

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 强制修改 ATF 源码 (原文照抄) ==========
echo "=== Patching ATF source for DDR4 ==="
mkdir -p plat/mediatek/mt7981/drivers/dram
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>
#define IAP_REBB_SWITCH 0x11D00A0C
#define IAP_IND 0x01
extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
extern int mt7981_ddr_size_limit;
extern int mt7981_dram_debug;
extern int mt7981_bga_pkg;
extern int mt7981_ddr3_freq;
void mtk_mem_init(void) {
    mt7981_use_ddr4 = 1;
    NOTICE("EMI: Using DDR%u settings\n", mt7981_use_ddr4 ? 4 : 3);
    mtk_mem_init_real();
}
void mtk_mem_dbg_print(const char *fmt, ...) {
    va_list args;
    if (!mt7981_dram_debug) return;
    va_start(args, fmt);
    (void)vprintf(fmt, args);
    va_end(args);
}
void mtk_mem_err_print(const char *fmt, ...) {
    const char *prefix_str; va_list args;
    prefix_str = plat_log_get_prefix(LOG_LEVEL_ERROR);
    while (*prefix_str != '\0') { (void)putchar(*prefix_str); prefix_str++; }
    va_start(args, fmt);
    (void)vprintf(fmt, args);
    va_end(args);
}
EOF

# ========== 2. 编译 ATF 全家桶 (最小物理修补：只编救砖必须件) ==========
echo "=== Building ATF for Rescue ==="
# 编译 NOR 版 (用于 32MB 救砖包)
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DDR_TYPE=ddr4 BOARD_BGA=1 LOG_LEVEL=20
cp -v build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin
cp -v build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-nor-bl31.bin

# 编译 RAM 版 (用于 UART 引导)
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DDR_TYPE=ddr4 BOARD_BGA=1 RAM_BOOT_UART_DL=1 LOG_LEVEL=20
cp -v build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-ram-1g.bin

# ========== 3. 编译 U-Boot (原文照抄) ==========
echo "=== Building U-Boot for Rescue ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-bl31.bin" --nt-fw u-boot.bin "$OUTPUT_DIR/uboot/fip-nor.bin"

# ========== 4. 物理缝合救砖镜像 (最小物理修补：无固件纯净版) ==========
echo "=== Stitching Spi-flash-32MB.bin (Rescue Only) ==="
cd "$OUTPUT_DIR/firmware"

# 创建 32MB 全 F 物理镜像
dd if=/dev/zero bs=1k count=32768 | tr '\000' '\377' > Spi-flash-32MB.bin
# 注入 BL2 (0x0)
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of=Spi-flash-32MB.bin conv=notrunc
# 注入 FIP (3.5MB / 3584k)
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of=Spi-flash-32MB.bin bs=1k seek=3584 conv=notrunc

# 诊断：由于不构建升级固件，4MB 后的分区保持全 F (空白)，此时镜像已可救回 U-Boot
echo "✅ Rescue bootloader stitched to Spi-flash-32MB.bin"

# ========== 5. 打包工具 (原文照抄) ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "=== [Audit] Final Product List ==="
ls -lh "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"
