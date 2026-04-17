#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
PARTS_DIR="$OUTPUT_DIR/parts"
BIN_DIR="$IMMORTALWRT_BUILD/bin/targets/mediatek/filogic"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware} "$PARTS_DIR" "$BIN_DIR"

# ---------- 1. 编译 ATF ----------
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

# 1G NOR (用于 SPI 救砖)
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

# ---------- 3. 打包 mtk_uartboot ----------
echo "=== 打包 mtk_uartboot ==="
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ---------- 4. 编译 OpenWrt 固件 ----------
echo "=== 编译 ImmortalWrt 固件 ==="
cd "$IMMORTALWRT_BUILD"
make -j$(nproc) V=s

# 收集 sysupgrade 固件
find bin/targets -type f -name "*sysupgrade*" -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

# ---------- 5. 提取内核与 rootfs ----------
echo "=== 提取内核与根文件系统 ==="
cd "$IMMORTALWRT_BUILD"
KERNEL_ELF=$(find build_dir/target-aarch64_cortex-a53_musl/linux-* -name vmlinux -type f | head -1)
KERNEL_DIR=$(dirname "$KERNEL_ELF")
KERNEL_BIN="$KERNEL_DIR/vmlinux.bin"
if [ ! -f "$KERNEL_BIN" ]; then
    aarch64-linux-gnu-objcopy -O binary "$KERNEL_ELF" "$KERNEL_BIN"
fi
ROOTFS_BIN=$(find build_dir/target-aarch64_cortex-a53_musl/root-* -name root.squashfs -type f | head -1)

cp -v "$KERNEL_BIN" "$PARTS_DIR/kernel.bin"
cp -v "$ROOTFS_BIN" "$PARTS_DIR/rootfs.bin"

# ---------- 6. 准备 Factory 分区 ----------
FACTORY_SRC="$MAIN_REPO/888/factory.bin"
if [ -f "$FACTORY_SRC" ]; then
    cp -v "$FACTORY_SRC" "$PARTS_DIR/factory.bin"
else
    echo "⚠️ 未找到 factory.bin，将创建空白占位文件（无线校准数据缺失）"
    dd if=/dev/zero bs=256k count=1 2>/dev/null | tr '\000' '\377' > "$PARTS_DIR/factory.bin"
fi

# ---------- 7. 复制合成所需文件到 BIN_DIR ----------
echo "=== 复制文件到 BIN_DIR 供 Makefile 合成 ==="
cp -v "$OUTPUT_DIR/atf/bl2-1g-nor.bin" "$BIN_DIR/bl2.img"
cp -v "$OUTPUT_DIR/uboot/fip-nor.bin" "$BIN_DIR/fip.bin"
cp -v "$PARTS_DIR/factory.bin" "$BIN_DIR/factory.bin"
cp -v "$PARTS_DIR/kernel.bin" "$BIN_DIR/kernel.bin"
cp -v "$PARTS_DIR/rootfs.bin" "$BIN_DIR/rootfs.bin"

# ---------- 8. 重新运行 make 以触发合成镜像 ----------
echo "=== 触发 OpenWrt 合成完整 32MB 镜像 ==="
cd "$IMMORTALWRT_BUILD"
make target/linux/compile

# 合成的镜像位于 bin/targets/mediatek/filogic/
FULL_IMAGE=$(find bin/targets/mediatek/filogic/ -name "spi-full-32mb.bin" -type f | head -1)
if [ -f "$FULL_IMAGE" ]; then
    cp -v "$FULL_IMAGE" "$OUTPUT_DIR/Spi-flash-32MB-full.bin"
    echo "✅ 完整镜像已生成: $OUTPUT_DIR/Spi-flash-32MB-full.bin"
else
    echo "❌ 未找到合成镜像，请检查 Makefile 中的合成步骤"
    exit 1
fi

echo "=========================================="
echo "✅ diy-part2 全部完成"
echo "输出目录: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo "=========================================="
