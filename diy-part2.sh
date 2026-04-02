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

# 编译 ATF（仅 NOR 和 RAM 版，用于救砖）
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram
# 此处省略 ATF 补丁代码（与之前相同，确保 DDR4 启用）

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin 2>/dev/null || true

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-ram-1g.bin 2>/dev/null || true

cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin

# 编译 U-Boot（NOR 版）
cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 生成 FIP
cd $IMMORTALWRT_BUILD_DIR
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"
cd $SOURCE_DIR/u-boot
$FIPTOOL create --soc-fw $STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin --nt-fw u-boot.bin u-boot.fip
cp u-boot.fip $OUTPUT_DIR/uboot/fip-nor.bin
cp u-boot.bin $OUTPUT_DIR/uboot/u-boot-nor.bin

# 构建救砖固件
cd "$IMMORTALWRT_BUILD_DIR"
make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log

mkdir -p "$OUTPUT_DIR/firmware"
SPI_IMAGE=$(find bin/targets/ -type f -name '*spi-nor*.bin' -size -34M | head -1)
if [ -z "$SPI_IMAGE" ]; then
    echo "❌ No SPI-NOR image found"
    exit 1
fi
cp "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"

# 打包 mtk_uartboot
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ Build complete"
