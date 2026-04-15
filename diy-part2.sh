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

# ========== 1. 强制修改 ATF 源码：开启 DDR4 逻辑 ==========
echo "=== Patching ATF source to force DDR4 ==="
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram

cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>

extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
extern int mt7981_ddr_size_limit;
extern int mt7981_dram_debug;
extern int mt7981_bga_pkg;

void mtk_mem_init(void)
{
    /* 1版核心修复：强制开启 DDR4 */
    mt7981_use_ddr4 = 1;
#ifdef DRAM_SIZE_LIMIT
    mt7981_ddr_size_limit = DRAM_SIZE_LIMIT;
#endif
    NOTICE("EMI: Using DDR%u settings (1GB Force)\n", mt7981_use_ddr4 ? 4 : 3);
    mtk_mem_init_real();
}

void mtk_mem_dbg_print(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    (void)vprintf(fmt, args);
    va_end(args);
}
void mtk_mem_err_print(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    (void)vprintf(fmt, args);
    va_end(args);
}
EOF

# ========== 2. 编译各版本 ATF (EMMC/NOR/RAM) ==========
echo "=== Building ATF binaries ==="
# 编译 1G EMMC 版
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-emmc.bin

# 编译 1G NOR 救砖版
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin

# 编译 RAM 调试版
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-ram-1g.bin

# 统一提取 bl31.bin
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-ddr4-bl31.bin"

# ========== 3. 编译 U-Boot 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
make -C ../arm-trusted-firmware/tools/fiptool
FIPTOOL="$SOURCE_DIR/arm-trusted-firmware/tools/fiptool/fiptool"

# 编译 EMMC 版 U-Boot
make clean
make mt7981_emmc_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-ddr4-bl31.bin" --nt-fw u-boot.bin $OUTPUT_DIR/uboot/fip-emmc.bin

# 编译 NOR 版 U-Boot (救援核心)
make clean
make mt7981_spim_nor_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-ddr4-bl31.bin" --nt-fw u-boot.bin $OUTPUT_DIR/uboot/fip-nor.bin

# ========== 4. 1版物理合成：救砖全家桶镜像 ==========
echo "=== 合成 1版 SPI-NOR 救砖全家桶 (32MB) ==="
RESCUE_BIN="$OUTPUT_DIR/firmware/SL3000_SPI_RESCUE_V1.bin"

# 创建 32MB 容器并填充 FF
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$RESCUE_BIN"
# 注入 BL2 (0x0)
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$RESCUE_BIN" conv=notrunc
# 注入 FIP (0x40000 / 256KB)
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$RESCUE_BIN" seek=512 conv=notrunc
# 注入 9秒拦截补丁
sed -i 's/bootdelay=[0-9]/bootdelay=9/g' "$RESCUE_BIN"

# 静默审计：验证 TOC 标志位
if ! dd if="$RESCUE_BIN" bs=1 skip=262144 count=4 2>/dev/null | grep -q "TOC"; then
    echo "❌ 1版合成失败：0x40000 处未发现 TOC 标志！"
    exit 1
fi
echo "✅ 1版全家桶合成成功：$RESCUE_BIN"

# ========== 5. 编译完整 ImmortalWrt 固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s
find bin/targets/ -type f \( -name "*sysupgrade*" -o -name "*.img.gz" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

echo "✅ Build Complete."
