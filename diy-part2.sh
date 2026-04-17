#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$OUTPUT_DIR"/{atf,uboot} "$PARTS_DIR"

# ---------- 1. 编译 ATF (修复 DDR4 BGA 参数) ----------
echo "=== Building ATF (DDR4, 1GB, BGA) ==="
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

# 1G eMMC 版 (备用)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp -v build/mt7981/release/bl31.bin "$OUTPUT_DIR/atf/bl31-1g-emmc.bin"

# 1G NOR 版 (用于 SPI 救砖)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"

# RAM 救砖版 (必须包含 BOARD_BGA=1 和 RAM_BOOT_UART_DL=1)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-ram-1g.bin"

# ---------- 2. 修正 U-Boot defconfig 并编译 ----------
echo "=== Patching U-Boot defconfig ==="
cd "$MAIN_REPO/u-boot"
make mt7981_spim_nor_rfb_defconfig

# 修正环境变量偏移和分区表
sed -i 's/CONFIG_ENV_OFFSET=0x0/CONFIG_ENV_OFFSET=0xC0000/' .config
sed -i 's/CONFIG_ENV_SIZE=0x10000/CONFIG_ENV_SIZE=0x40000/' .config
sed -i 's|CONFIG_MTDPARTS_DEFAULT=.*|CONFIG_MTDPARTS_DEFAULT="nor0:256k(bl2),512k(fip),256k(u-boot-env),2m(factory),-(firmware)"|' .config

make olddefconfig
make -j$(nproc)

# 复制产物
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ---------- 3. 手动合成 FIP (无需 fiptool) ----------
echo "=== Manually assembling FIP ==="
cd "$OUTPUT_DIR/uboot"
# 创建 FIP 容器 (BL31 + U-Boot)
cat "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" u-boot-nor.bin > fip-nor.bin
echo "✅ fip-nor.bin created ($(stat -c%s fip-nor.bin) bytes)"

# ---------- 4. 打包 mtk_uartboot ----------
echo "=== Packaging mtk_uartboot ==="
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ---------- 5. 准备 Factory 占位文件 ----------
FACTORY_SRC="$MAIN_REPO/888/factory.bin"
if [ -f "$FACTORY_SRC" ]; then
    cp -v "$FACTORY_SRC" "$PARTS_DIR/factory.bin"
else
    echo "⚠️ 未找到 factory.bin，创建 2MB 空白占位文件"
    dd if=/dev/zero bs=2M count=1 2>/dev/null | tr '\000' '\377' > "$PARTS_DIR/factory.bin"
fi

# ---------- 6. 合成 32MB 救砖镜像 ----------
echo "=== Creating Spi-flash-32MB-rescue.bin ==="
RESCUE_BIN="$OUTPUT_DIR/Spi-flash-32MB-rescue.bin"
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"

# BL2 @ 0x0
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
# FIP @ 0x40000 (256KB)
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
# Factory @ 0x180000 (1.5MB)
dd if="$PARTS_DIR/factory.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none

echo "✅ 救砖镜像已生成: $RESCUE_BIN"
ls -lh "$RESCUE_BIN"

echo "=========================================="
echo "✅ 救砖全家桶构建完成"
echo "输出目录: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo "=========================================="
