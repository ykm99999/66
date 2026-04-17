#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
PARTS_DIR="$OUTPUT_DIR/parts"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware} "$PARTS_DIR"

# ---------- 1. 编译 OpenWrt 固件 ----------
echo "=== 编译 ImmortalWrt 固件 ==="
cd "$IMMORTALWRT_BUILD"
make -j$(nproc) V=s

# 收集 sysupgrade 固件
find bin/targets -type f -name "*sysupgrade*" -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

# ---------- 2. 编译 ATF ----------
echo "=== 编译 ATF (DDR4, 1GB) ==="
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

# ---------- 3. 编译 U-Boot ----------
echo "=== 编译 U-Boot (eMMC) ==="
cd "$MAIN_REPO/u-boot"
make clean
make mt7981_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)
"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-emmc.bin
cp -v fip-emmc.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

echo "=== 编译 U-Boot (NOR) ==="
make clean
make mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)
"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-nor.bin
cp -v fip-nor.bin "$OUTPUT_DIR/uboot/"
cp -v u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ---------- 4. 打包 mtk_uartboot ----------
echo "=== 打包 mtk_uartboot ==="
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ---------- 5. 提取内核与 rootfs，合成 firmware.bin ----------
echo "=== 提取内核与根文件系统 ==="
cd "$IMMORTALWRT_BUILD"
KERNEL_ELF=$(find build_dir/target-aarch64_cortex-a53_musl/linux-* -name vmlinux -type f | head -1)
KERNEL_DIR=$(dirname "$KERNEL_ELF")
KERNEL_BIN="$KERNEL_DIR/vmlinux.bin"
if [ ! -f "$KERNEL_BIN" ]; then
    aarch64-linux-gnu-objcopy -O binary "$KERNEL_ELF" "$KERNEL_BIN"
fi
ROOTFS_BIN=$(find build_dir/target-aarch64_cortex-a53_musl/root-* -name root.squashfs -type f | head -1)

FIRMWARE_BIN="$PARTS_DIR/firmware.bin"
cat "$KERNEL_BIN" "$ROOTFS_BIN" > "$FIRMWARE_BIN"
echo "✅ firmware.bin 已生成 ($(stat -c%s "$FIRMWARE_BIN") 字节)"

# ---------- 6. 检查 Factory 分区 ----------
FACTORY_BIN="$PARTS_DIR/factory.bin"
if [ ! -f "$FACTORY_BIN" ]; then
    echo "⚠️ 未找到 factory.bin，将创建空白占位文件（无线校准数据缺失）"
    dd if=/dev/zero bs=1M count=2 2>/dev/null | tr '\000' '\377' > "$FACTORY_BIN"
fi

# ---------- 7. 合成 32MB 全镜像 ----------
echo "=== 合成 Spi-flash-32MB-full.bin ==="
FULL_BIN="$OUTPUT_DIR/Spi-flash-32MB-full.bin"
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$FULL_BIN"

dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$FULL_BIN" bs=1 conv=notrunc status=none
dd if="$FACTORY_BIN" of="$FULL_BIN" bs=1 seek=$((0x180000)) conv=notrunc status=none
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$FULL_BIN" bs=1 seek=$((0x380000)) conv=notrunc status=none
dd if="$FIRMWARE_BIN" of="$FULL_BIN" bs=1 seek=$((0x580000)) conv=notrunc status=none

echo "✅ 完整镜像已生成: $FULL_BIN"
ls -lh "$FULL_BIN"

echo "=========================================="
echo "✅ diy-part2 全部完成"
echo "输出目录: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo "=========================================="
