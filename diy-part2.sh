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

# ========== 编译 ATF（与成功案例完全一致，无任何补丁） ==========
echo "=== Building ATF 512M (EMMC) ==="
cd $SOURCE_DIR/arm-trusted-firmware
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 512M emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 512M emmc"

if command -v strings &> /dev/null; then
    if strings build/mt7981/release/bl2.bin | grep -qi "DDR4"; then
        echo "✅ 512M BL2 is DDR4"
    else
        echo "❌ 512M BL2 is NOT DDR4, check patching!"
        exit 1
    fi
fi

echo "=== Building ATF 1G (EMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 1G emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 1G emmc"

if command -v strings &> /dev/null; then
    if strings build/mt7981/release/bl2.bin | grep -qi "DDR4"; then
        echo "✅ 1G BL2 is DDR4"
    else
        echo "❌ 1G BL2 is NOT DDR4, check patching!"
        exit 1
    fi
fi

echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

echo "=== Building ATF RAM (1G DDR4) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.bin \; 2>/dev/null || echo "No bl2.bin for RAM"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-ram-1g.elf \; 2>/dev/null || echo "No bl2.elf for RAM"

if [ ! -f "$OUTPUT_DIR/atf/bl2-ram-1g.bin" ]; then
    echo "❌ bl2-ram-1g.bin not generated! Check ATF compilation for RAM."
    exit 1
else
    echo "✅ bl2-ram-1g.bin generated successfully"
fi

if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found after ATF compilation!"
    exit 1
fi

cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" || { echo "❌ Failed to copy bl31.bin for emmc"; exit 1; }
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" || { echo "❌ Failed to copy bl31.bin for nor"; exit 1; }

ls -la "$STAGING_DIR_IMAGE"/mt7981-*.bin || { echo "❌ Copied bl31 files missing"; exit 1; }

echo "=== Compiling fiptool from ATF ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ========== 编译 U-Boot (eMMC版) 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
echo "=== Building U-Boot (eMMC) ==="
make clean
if [ -f configs/mt7981_emmc_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
else
    echo "❌ mt7981_emmc_rfb_defconfig not found!"
    exit 1
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    echo "⚠️ fip.bin not generated for eMMC, creating manually..."
    if [ -f "$FIPTOOL" ]; then
        if [ ! -f "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" ]; then
            echo "❌ mt7981-emmc-ddr4-bl31.bin not found!"
            exit 1
        fi
        "$FIPTOOL" create \
            --soc-fw "$STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin" \
            --nt-fw u-boot.bin \
            u-boot.fip
        cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin"
    else
        echo "❌ fiptool not found, cannot create FIP"
        exit 1
    fi
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-emmc.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-emmc.bin" 2>/dev/null
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ========== 编译 U-Boot (NOR版) 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
echo "=== Building U-Boot (NOR) ==="
make clean
if [ -f configs/mt7981_spim_nor_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
else
    echo "❌ mt7981_spim_nor_rfb_defconfig not found, cannot build NOR U-Boot"
    exit 1
fi
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    echo "⚠️ fip.bin not generated for NOR, creating manually..."
    if [ -f "$FIPTOOL" ]; then
        if [ ! -f "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" ]; then
            echo "❌ mt7981-nor-ddr4-bl31.bin not found!"
            exit 1
        fi
        "$FIPTOOL" create \
            --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" \
            --nt-fw u-boot.bin \
            u-boot.fip
        cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
    else
        echo "❌ fiptool not found, cannot create FIP"
        exit 1
    fi
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 编译 ImmortalWrt 固件（只生成救砖镜像） ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"

# 检查救砖设备是否启用
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ Device sl_3000-spi-nor not enabled in .config!"
    exit 1
fi

make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed! Last 100 lines of build.log:"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
cp build.log "$OUTPUT_DIR/firmware/"

# 复制 SPI-NOR 救砖镜像并重命名
SPI_IMAGE=$(find bin/targets/ -type f -name '*sl_3000-spi-nor*sysupgrade.bin' -size -34M | head -1)
if [ -z "$SPI_IMAGE" ]; then
    echo "❌ No SPI-NOR rescue image found!"
    echo "Available images:"
    find bin/targets/ -type f -name '*.bin' | head -20
    exit 1
fi

cp -v "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
echo "✅ SPI-NOR rescue image copied to Spi-flash-32MB.bin"

# ========== 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
if [ $? -ne 0 ] || [ ! -f "$OUTPUT_DIR/mtk_uartboot.tar.gz" ]; then
    echo "❌ Failed to package mtk_uartboot"
    exit 1
fi

echo "✅ Build complete. Output directory contents:"
ls -la "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"
echo "mtk_uartboot.tar.gz is in $OUTPUT_DIR"
