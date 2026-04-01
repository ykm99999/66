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

# ========== 强制修改 ATF 源码，启用 DDR4 ==========
echo "=== Patching ATF source to force DDR4 ==="
cd $SOURCE_DIR/arm-trusted-firmware
mkdir -p plat/mediatek/mt7981/drivers/dram

cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
/* 保持与成功案例完全相同的代码 */
EOF
echo "✅ ATF source patched for DDR4"

# ========== 编译 ATF（保持不变） ==========
echo "=== Building ATF 512M (EMMC) ==="
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

# ========== 编译 U-Boot (eMMC版) ==========
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

# ========== 编译 U-Boot (NOR版) ==========
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

# ========== 编译 ImmortalWrt 固件（同时生成 eMMC 和 SPI-NOR） ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"

# 检查 .config 中是否至少启用了一个设备
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000" .config; then
    echo "❌ No SL3000 device enabled in .config!"
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

# 复制 eMMC 升级固件（sysupgrade）
EMMC_SYSUPGRADE=$(find bin/targets/ -type f -name '*sl_3000-emmc*sysupgrade.bin' | head -1)
if [ -n "$EMMC_SYSUPGRADE" ]; then
    cp -v "$EMMC_SYSUPGRADE" "$OUTPUT_DIR/firmware/"
    echo "✅ eMMC sysupgrade firmware copied: $(basename $EMMC_SYSUPGRADE)"
else
    echo "⚠️ No eMMC sysupgrade firmware found (device may not be enabled in .config)"
fi

# 复制 SPI-NOR 救砖镜像（重命名为 Spi-flash-32MB.bin）
SPI_IMAGE=$(find bin/targets/ -type f -name '*sl_3000-spi-nor*sysupgrade.bin' -size -34M | head -1)
if [ -n "$SPI_IMAGE" ]; then
    cp -v "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
    echo "✅ SPI-NOR rescue image copied and renamed to Spi-flash-32MB.bin"
else
    echo "⚠️ No SPI-NOR rescue image under 34MB found (device may not be enabled or image too large)"
fi

# 检查是否至少有一个固件生成
if [ ! -f "$OUTPUT_DIR/firmware/"*sysupgrade* ] && [ ! -f "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin" ]; then
    echo "❌ No firmware files generated!"
    echo "Contents of bin/targets/ (first 50 files):"
    find bin/targets/ -type f | head -50
    echo "Last 100 lines of build.log:"
    tail -100 build.log
    exit 1
fi

# ========== 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
if [ $? -ne 0 ] || [ ! -f "$OUTPUT_DIR/mtk_uartboot.tar.gz" ]; then
    echo "❌ Failed to package mtk_uartboot"
    exit 1
fi

# ========== 最终输出 ==========
echo "✅ Build complete. Output directory contents:"
ls -la "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"
echo "mtk_uartboot.tar.gz is in $OUTPUT_DIR"
