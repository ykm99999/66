#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$OUTPUT_DIR"/{atf,uboot}

# ========== 环境检查 ==========
if ! which aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "❌ 未找到 aarch64-linux-gnu-gcc，请先安装 gcc-aarch64-linux-gnu"
    exit 1
fi

[ -d "$MAIN_REPO/arm-trusted-firmware" ] || { echo "❌ 缺少 $MAIN_REPO/arm-trusted-firmware"; exit 1; }
[ -d "$MAIN_REPO/u-boot" ] || { echo "❌ 缺少 $MAIN_REPO/u-boot"; exit 1; }
[ -d "$MAIN_REPO/mtk_uartboot" ] || { echo "❌ 缺少 $MAIN_REPO/mtk_uartboot"; exit 1; }

# ========== 编译 ATF ==========
echo "=== Building ATF (DDR4, 1GB) ==="
cd "$MAIN_REPO/arm-trusted-firmware"
mkdir -p plat/mediatek/mt7981/drivers/dram

cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>
extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
void mtk_mem_init(void) {
    mt7981_use_ddr4 = 1;
    NOTICE("EMI: Forced DDR4 for SL3000\n");
    mtk_mem_init_real();
}
void mtk_mem_dbg_print(const char *fmt, ...) {}
void mtk_mem_err_print(const char *fmt, ...) {}
EOF

# 1G eMMC
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp -v build/mt7981/release/bl31.bin "$OUTPUT_DIR/atf/bl31-1g-emmc.bin"

# 1G NOR
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"

# RAM (救砖)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-ram-1g.bin"

# ========== 编译 fiptool（修复 /tools 权限问题） ==========
echo "=== Building fiptool ==="
cd "$MAIN_REPO/arm-trusted-firmware"
mkdir -p build/mt7981/release/tools/fiptool
make -C tools/fiptool CROSS_COMPILE= HOSTCC=gcc BUILD_BASE="$PWD/build" V=1
FIPTOOL="$PWD/tools/fiptool/fiptool"
if [ ! -x "$FIPTOOL" ]; then
    echo "❌ fiptool 编译失败"
    exit 1
fi

# ========== 编译 U-Boot eMMC ==========
echo "=== Building U-Boot (eMMC) ==="
cd "$MAIN_REPO/u-boot"
make clean
make mt7981_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)

"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-emmc.bin
cp -v fip-emmc.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 编译 U-Boot NOR ==========
echo "=== Building U-Boot (NOR) ==="
make clean
make mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)

"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-nor.bin
cp -v fip-nor.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 打包 mtk_uartboot ==========
echo "=== Packaging mtk_uartboot ==="
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ========== 合成 Spi-flash-32MB.bin ==========
echo "=== Creating Spi-flash-32MB.bin ==="
cd "$OUTPUT_DIR"
BL2_NOR="atf/bl2-1g-nor.bin"
FIP_NOR="uboot/fip-nor.bin"
OUTPUT_BIN="Spi-flash-32MB.bin"

[ -f "$BL2_NOR" ] || { echo "❌ 缺少 $BL2_NOR"; exit 1; }
[ -f "$FIP_NOR" ] || { echo "❌ 缺少 $FIP_NOR"; exit 1; }

dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$OUTPUT_BIN"
dd if="$BL2_NOR" of="$OUTPUT_BIN" bs=1 conv=notrunc status=none
dd if="$FIP_NOR" of="$OUTPUT_BIN" bs=1 seek=262144 conv=notrunc status=none

echo "✅ 合成完成: $OUTPUT_BIN"
ls -lh "$OUTPUT_BIN"

echo "=========================================="
echo "✅ 救砖全家桶构建完成"
echo "输出目录: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo "=========================================="
