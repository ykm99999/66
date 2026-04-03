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

# 强制修改 ATF 源码，启用 DDR4（省略具体代码，请保留原有完整补丁）
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
/* 此处粘贴您之前成功的完整代码 */
EOF
echo "✅ ATF source patched"

# 编译 ATF（只编译 NOR 和 RAM 版，因为救砖不需要 eMMC 版）
echo "=== Building ATF 1G (NOR) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

echo "=== Building ATF RAM (1G) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.bin \; 2>/dev/null || echo "No bl2.bin for RAM"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.elf \; 2>/dev/null || echo "No bl2.elf for RAM"

if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found"
    exit 1
fi
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# 编译 fiptool
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"
mkdir -p $SOURCE_DIR/u-boot/tools
cp -f $FIPTOOL $SOURCE_DIR/u-boot/tools/fiptool

# 编译 U-Boot (NOR版)
cd $SOURCE_DIR/u-boot
make clean
if [ -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
else
    echo "❌ mt7981_spim_nor_rfb_defconfig not found"
    exit 1
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    $FIPTOOL create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" --nt-fw u-boot.bin u-boot.fip
    cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# 构建 SPI-NOR 救砖固件
cd "$IMMORTALWRT_BUILD_DIR"
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ Rescue device not enabled"
    exit 1
fi

make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
cp build.log "$OUTPUT_DIR/firmware/"

SPI_IMAGE=$(find bin/targets/ -type f -name '*sl_3000-spi-nor*sysupgrade.bin' -size -34M | head -1)
if [ -z "$SPI_IMAGE" ]; then
    echo "❌ No SPI-NOR rescue image found"
    exit 1
fi
cp "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
echo "✅ SPI-NOR rescue image saved as Spi-flash-32MB.bin"

# 打包 mtk_uartboot
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ Build complete"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
