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

# 注入强制 DDR4 补丁
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

# 1G eMMC 版本 (BL2 + BL31)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp -v build/mt7981/release/bl31.bin "$OUTPUT_DIR/atf/bl31-1g-emmc.bin"

# 1G NOR 版本 (用于 SPI Flash 救砖)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"

# RAM 版本 (用于 UART 救砖)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-ram-1g.bin"

# ========== 编译 fiptool（修复权限错误） ==========
echo "=== Building fiptool ==="
cd "$MAIN_REPO/arm-trusted-firmware/tools/fiptool"
make clean
make CC=gcc
cd "$MAIN_REPO/arm-trusted-firmware"
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

# 生成 eMMC FIP 镜像
"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-emmc.bin
cp -v fip-emmc.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 编译 U-Boot NOR (SPI Flash) ==========
echo "=== Building U-Boot (NOR) ==="
make clean
make mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)

# 生成 NOR FIP 镜像
"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-nor.bin
cp -v fip-nor.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 打包 mtk_uartboot ==========
echo "=== Packaging mtk_uartboot ==="
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ========== 合成 SPI Flash 32MB 全镜像（编程器烧录用） ==========
echo "=== Creating Spi-flash-32MB.bin for programmer ==="
cd "$OUTPUT_DIR"

BL2_NOR="atf/bl2-1g-nor.bin"
FIP_NOR="uboot/fip-nor.bin"
OUTPUT_BIN="Spi-flash-32MB.bin"

if [ ! -f "$BL2_NOR" ]; then
    echo "❌ 缺少 $BL2_NOR，无法合成全镜像"
    exit 1
fi
if [ ! -f "$FIP_NOR" ]; then
    echo "❌ 缺少 $FIP_NOR，无法合成全镜像"
    exit 1
fi

# 创建 32MB 空文件，全部填充 0xFF（模拟擦除状态）
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$OUTPUT_BIN"

# 写入 BL2（偏移 0x0）
dd if="$BL2_NOR" of="$OUTPUT_BIN" bs=1 conv=notrunc status=none

# 写入 FIP（偏移 0x40000 = 262144 字节）
dd if="$FIP_NOR" of="$OUTPUT_BIN" bs=1 seek=262144 conv=notrunc status=none

echo "✅ 合成完成: $OUTPUT_DIR/$OUTPUT_BIN"
ls -lh "$OUTPUT_BIN"

# ========== 最终报告 ==========
echo "=========================================="
echo "✅ 救砖全家桶构建完成"
echo "输出目录: $OUTPUT_DIR"
echo "包含文件:"
ls -la "$OUTPUT_DIR"
echo "=========================================="
