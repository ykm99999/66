#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 2版核心物理修补：解决 DTS 路径失踪 (No such file or directory) ==========
echo "=== 2版物理修补：同步补全内核 DTS 搜索路径 ==="
# 溯源诊断：根据日志 cc1 报错，内核在寻找 mediatek/mediatek/ 级联路径
KERNEL_DTS_DIR="build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/linux-6.6.127/arch/arm64/boot/dts/mediatek/mediatek"
mkdir -p "$KERNEL_DTS_DIR"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$KERNEL_DTS_DIR/" || echo "⚠️ 提示：编译尚未开始，路径将在编译过程中建立"

# 同时在 target 级注入，确保稳健性
mkdir -p "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mediatek"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mediatek/"

# ========== 强制修改 ATF 源码，启用 DDR4 (原文照抄) ==========
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

void mtk_mem_init(void) {
	mt7981_use_ddr4 = 1; /* 强制锁定 DDR4 物理初始化 */
#ifdef DRAM_SIZE_LIMIT
	mt7981_ddr_size_limit = DRAM_SIZE_LIMIT;
#endif
#if defined(BOARD_BGA)
	mt7981_bga_pkg = 1;
#endif
	NOTICE("EMI: Using DDR%u settings\n", mt7981_use_ddr4 ? 4 : 3);
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

# ========== 编译 ATF (原文照抄) ==========
echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# ========== 编译 U-Boot (NOR版) 并生成 FIP (原文照抄) ==========
cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# 物理合成 FIP
make -C $SOURCE_DIR/arm-trusted-firmware/tools/fiptool CROSS_COMPILE=
$SOURCE_DIR/arm-trusted-firmware/tools/fiptool/fiptool create \
    --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" \
    --nt-fw u-boot.bin \
    "$OUTPUT_DIR/uboot/fip-nor.bin"

# ========== 1版物理合成：救砖全家桶 (最小修补) ==========
echo "=== 合成 32MB 救砖固件 ==="
RESCUE_BIN="$OUTPUT_DIR/firmware/SL3000_SPI_RESCUE_V2.bin"
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$RESCUE_BIN" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$RESCUE_BIN" seek=512 conv=notrunc
sed -i 's/bootdelay=[0-9]/bootdelay=9/g' "$RESCUE_BIN"

# ========== 编译 ImmortalWrt 完整固件 (原文照抄) ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"
# 物理锁定设备选项
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
make defconfig
make -j$(nproc) V=s

# 收集产物
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

echo "✅ 2版脚本执行完毕，物理路径已补齐。"
