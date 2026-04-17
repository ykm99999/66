#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$OUTPUT_DIR"/{atf,uboot} "$PARTS_DIR"

# ---------- 1. 编译 ATF ----------
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

# RAM 救砖版
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-ram-1g.bin"

# 编译 fiptool
cd tools/fiptool
make clean
make CC=gcc
cd "$MAIN_REPO/arm-trusted-firmware"
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ---------- 2. 编译 U-Boot ----------
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

echo "=== Building U-Boot (NOR) ==="
make clean
make mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)
"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-nor.bin
cp -v fip-nor.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ---------- 3. 打包 mtk_uartboot ----------
echo "=== Packaging mtk_uartboot ==="
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ---------- 4. 准备 Factory 占位文件 ----------
FACTORY_SRC="$MAIN_REPO/888/factory.bin"
if [ -f "$FACTORY_SRC" ]; then
    cp -v "$FACTORY_SRC" "$PARTS_DIR/factory.bin"
else
    echo "⚠️ 未找到 factory.bin，创建 2MB 空白占位文件"
    dd if=/dev/zero bs=2M count=1 2>/dev/null | tr '\000' '\377' > "$PARTS_DIR/factory.bin"
fi

# ---------- 5. 合成 32MB 救砖镜像 (仅 BL2 + FIP) ----------
echo "=== Creating Spi-flash-32MB-rescue.bin ==="
RESCUE_BIN="$OUTPUT_DIR/Spi-flash-32MB-rescue.bin"
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# 写入 BL2 (0x0)
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none

# 写入 FIP (0x40000)
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none

# 写入 Factory (0x180000) —— 可选，但为了分区表完整性
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none

echo "✅ 救砖镜像已生成: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"

echo "=========================================="
echo "✅ 救砖全家桶构建完成"
echo "输出目录: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo "=========================================="
