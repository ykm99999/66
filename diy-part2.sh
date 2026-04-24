#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat "$WORKSPACE/build-dir.txt")
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 修补 ATF 强制 DDR4 ==========
echo "=== Patching ATF source for DDR4 ==="
cd "$WORKSPACE/arm-trusted-firmware"
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
	if (!mt7981_dram_debug) return;
	va_start(args, fmt);
	(void)vprintf(fmt, args);
	va_end(args);
}

void mtk_mem_err_print(const char *fmt, ...)
{
	const char *prefix_str = plat_log_get_prefix(LOG_LEVEL_ERROR);
	va_list args;
	while (*prefix_str != '\0') { (void)putchar(*prefix_str); prefix_str++; }
	va_start(args, fmt);
	(void)vprintf(fmt, args);
	va_end(args);
}
EOF
echo "✅ ATF patched"

# ========== 编译 ATF 各个变体 ==========
build_atf() {
    local desc="$1"
    shift
    echo "=== Building ATF: $desc ==="
    make clean
    make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 "$@"
}

# 512M eMMC
build_atf "512M eMMC" BOOT_DEVICE=emmc DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} "$OUTPUT_DIR/atf/bl2-512m-emmc.bin" \; 2>/dev/null || true

# 1G eMMC
build_atf "1G eMMC" BOOT_DEVICE=emmc DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} "$OUTPUT_DIR/atf/bl2-1g-emmc.bin" \; 2>/dev/null || true

# 1G NOR
build_atf "1G NOR" BOOT_DEVICE=nor DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} "$OUTPUT_DIR/atf/bl2-1g-nor.bin" \; 2>/dev/null || true

# RAM 版（救砖用）
build_atf "RAM 1G DDR4" BOOT_DEVICE=ram DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} "$OUTPUT_DIR/atf/bl2-ram-1g.bin" \;

if [ ! -f "$OUTPUT_DIR/atf/bl2-ram-1g.bin" ]; then
    echo "❌ bl2-ram-1g.bin 未生成！"
    exit 1
fi
echo "✅ bl2-ram-1g.bin 生成成功"

# 复制 bl31.bin
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin"
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# ========== 编译 fiptool ==========
echo "=== Compiling fiptool ==="
make fiptool BUILD_BASE="$PWD/build" HOSTCC=gcc
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ========== 编译 U-Boot eMMC ==========
cd "$WORKSPACE/u-boot"
echo "=== Building U-Boot (eMMC) ==="
make clean
if [ ! -f configs/mt7981_emmc_rfb_defconfig ]; then
    echo "❌ mt7981_emmc_rfb_defconfig not found"
    exit 1
fi
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    "$FIPTOOL" create \
        --soc-fw "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" \
        --nt-fw u-boot.bin \
        u-boot.fip
    cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin"
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-emmc.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin"
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 编译 U-Boot NOR ==========
echo "=== Building U-Boot (NOR) ==="
make clean
if [ ! -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    echo "❌ mt7981_spim_nor_rfb_defconfig not found"
    exit 1
fi
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    "$FIPTOOL" create \
        --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" \
        --nt-fw u-boot.bin \
        u-boot.fip
    cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 编译 ImmortalWrt 固件 ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config || {
    echo "❌ 设备未启用"
    exit 1
}

# 预先解压内核并修复交互选项
echo "=== Preparing kernel config (silent) ==="
make target/linux/prepare V=s 2>&1 | tail -20
KERNEL_BUILD_DIR=$(find build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic -maxdepth 1 -type d -name "linux-*" | head -1)
if [ -n "$KERNEL_BUILD_DIR" ] && [ -f "$KERNEL_BUILD_DIR/Makefile" ]; then
    echo "Setting kernel options in $KERNEL_BUILD_DIR"
    SCRIPTS_CONFIG="$KERNEL_BUILD_DIR/scripts/config"
    if [ ! -f "$SCRIPTS_CONFIG" ]; then
        echo "❌ $SCRIPTS_CONFIG not found"
        exit 1
    fi
    # 设置页面大小
    "$SCRIPTS_CONFIG" --file "$KERNEL_BUILD_DIR/.config" --enable ARM64_4K_PAGES
    "$SCRIPTS_CONFIG" --file "$KERNEL_BUILD_DIR/.config" --disable ARM64_16K_PAGES
    "$SCRIPTS_CONFIG" --file "$KERNEL_BUILD_DIR/.config" --disable ARM64_64K_PAGES
    # 修复 NVMEM 依赖
    "$SCRIPTS_CONFIG" --file "$KERNEL_BUILD_DIR/.config" --enable NVMEM
    # 应用配置
    make -C "$KERNEL_BUILD_DIR" olddefconfig ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
else
    echo "WARNING: Kernel build directory not found, build may prompt for input."
fi

echo "=== Starting full firmware build ==="
make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ 固件编译失败，最后 100 行："
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
cp build.log "$OUTPUT_DIR/firmware/"

if ! find "$OUTPUT_DIR/firmware" -name "*sysupgrade*" | grep -q .; then
    echo "❌ 未生成 sysupgrade 固件"
    find bin/targets/ -type f | head -50
    exit 1
fi

# ========== 打包 mtk_uartboot ==========
cd "$WORKSPACE/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
if [ ! -f "$OUTPUT_DIR/mtk_uartboot.tar.gz" ]; then
    echo "❌ mtk_uartboot 打包失败"
    exit 1
fi

echo "✅ 所有组件构建完成！"
ls -la "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"
