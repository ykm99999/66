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

# ========== 新路径定义（指向 hanwckf 源码子目录） ==========
ATF_DIR="$SOURCE_DIR/bl-mt798x/atf-20250711"
UBOOT_DIR="$SOURCE_DIR/bl-mt798x/uboot-mtk-20250711"

# ========== 编译 ATF (hanwckf，仅 NOR 版) ==========
echo "=== Building ATF from hanwckf source (NOR) ==="
cd $ATF_DIR
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found"
    exit 1
fi
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# ========== 编译 fiptool ==========
echo "=== Compiling fiptool ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"
mkdir -p $UBOOT_DIR/tools
cp -f $FIPTOOL $UBOOT_DIR/tools/fiptool

# ========== 编译 U-Boot (hanwckf，NOR 版) ==========
cd $UBOOT_DIR
echo "=== Building U-Boot from hanwckf source (NOR) ==="
make clean

# 自动选择 SPI-NOR 的 defconfig
if [ -f configs/mt7981b_nor_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981b_nor_defconfig
elif [ -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
else
    echo "❌ No suitable defconfig found for SPI-NOR!"
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

# ========== 构建 ImmortalWrt 救砖固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
echo "=== Building ImmortalWrt Rescue Firmware ==="

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ Rescue device not enabled in .config"
    exit 1
fi

make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed! Last 100 lines:"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
cp build.log "$OUTPUT_DIR/firmware/"

# 复制 SPI‑NOR 救砖镜像
SPI_IMAGE=$(find bin/targets/ -type f -name '*sl_3000-spi-nor*sysupgrade.bin' -size -34M | head -1)
if [ -z "$SPI_IMAGE" ]; then
    echo "❌ No SPI-NOR rescue image found"
    exit 1
fi
cp -v "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
echo "✅ SPI-NOR rescue image saved as Spi-flash-32MB.bin"

# ========== 生成完整的 32MB SPI‑NOR 镜像（包含 BL2、FIP、firmware） ==========
echo "=== Creating full 32MB SPI‑NOR image ==="
FULL_IMAGE="$OUTPUT_DIR/firmware/SL3000-full-spi-nor-32mb.bin"

dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$FULL_IMAGE"
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$FULL_IMAGE" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$FULL_IMAGE" seek=$((0x380000)) bs=1 conv=notrunc
dd if="$OUTPUT_DIR/firmware/Spi-flash-32MB.bin" of="$FULL_IMAGE" seek=$((0x580000)) bs=1 conv=notrunc

echo "✅ Full 32MB SPI‑NOR image created: $FULL_IMAGE"
ls -lh "$FULL_IMAGE"

# ========== 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ Build complete"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
