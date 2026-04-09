#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat "$WORKSPACE/build-dir.txt")
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 路径定义 ==========
ATF_DIR="$SOURCE_DIR/arm-trusted-firmware"
UBOOT_DIR="$SOURCE_DIR/u-boot"

# ========== 编译 ATF（官方源，NOR 版） ==========
echo "=== Building ATF (official, NOR) ==="
cd $ATF_DIR
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DDR_TYPE=ddr4

if [ ! -f build/mt7981/release/bl2.bin ]; then
    echo "❌ bl2.bin not found"
    exit 1
fi
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"

if [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ bl31.bin not found"
    exit 1
fi
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# ========== 编译 fiptool ==========
echo "=== Compiling fiptool ==="
make fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"
if [ ! -f "$FIPTOOL" ]; then
    echo "❌ fiptool not generated"
    exit 1
fi
mkdir -p $UBOOT_DIR/tools
cp -f $FIPTOOL $UBOOT_DIR/tools/fiptool
echo "✅ fiptool compiled"

# ========== 准备 U-Boot：复制自定义设备树 ==========
cd $UBOOT_DIR
echo "=== Copying custom device tree to U-Boot ==="
cp -v $CONFIG_DIR/mt7981b-sl3000-emmc.dts arch/arm/dts/

# ========== 编译 U-Boot ==========
echo "=== Building U-Boot (custom defconfig) ==="
make clean

if [ -f configs/mt7981_nor_emmc_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_nor_emmc_rfb_defconfig
else
    echo "❌ mt7981_nor_emmc_rfb_defconfig not found"
    exit 1
fi

echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f u-boot.fip ]; then
    echo "❌ u-boot.fip not generated"
    exit 1
fi
cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"
echo "✅ U-Boot compiled"

# ========== 构建 ImmortalWrt 救砖固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
echo "=== Building ImmortalWrt Rescue Firmware ==="

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
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

RESCUE_IMAGE=$(find bin/targets/ -type f \( -name '*mt7981_sl3000_spi_rescue*initramfs*.bin' -o -name 'rescue.bin' \) | head -1)
if [ -z "$RESCUE_IMAGE" ]; then
    echo "❌ No rescue image found"
    exit 1
fi
cp -v "$RESCUE_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
echo "✅ Rescue image saved as Spi-flash-32MB.bin"

# ========== 准备完整 SPI‑NOR 镜像所需的其他分区文件 ==========
BACKUP_DIR="$SOURCE_DIR/original_backup"
mkdir -p "$BACKUP_DIR"

prepare_partition() {
    local name=$1
    local size=$2
    local output_file="$OUTPUT_DIR/atf/${name}.bin"
    local backup_file="$BACKUP_DIR/${name}.bin"

    if [ -f "$backup_file" ]; then
        echo "Using backup: $backup_file"
        cp "$backup_file" "$output_file"
    elif [ -f "$output_file" ]; then
        echo "Using existing: $output_file"
    else
        echo "⚠️  Warning: $name.bin not found, creating empty (0xFF) file of size $size bytes"
        dd if=/dev/zero bs=$size count=1 2>/dev/null | tr '\000' '\377' > "$output_file"
    fi
}

if [ ! -f "$OUTPUT_DIR/atf/bl2-1g-nor.bin" ]; then
    echo "❌ bl2-1g-nor.bin missing"
    exit 1
fi
cp "$OUTPUT_DIR/atf/bl2-1g-nor.bin" "$OUTPUT_DIR/atf/BL2.bin"

prepare_partition "u-boot-env" 65536
prepare_partition "Config" 458752
prepare_partition "Factory" 2097152

if [ ! -f "$OUTPUT_DIR/uboot/fip-nor.bin" ]; then
    echo "❌ fip-nor.bin missing"
    exit 1
fi
cp "$OUTPUT_DIR/uboot/fip-nor.bin" "$OUTPUT_DIR/atf/FIP.bin"

cp "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin" "$OUTPUT_DIR/atf/firmware.bin"
prepare_partition "Product" 131072
prepare_partition "Custom" 1441792

# ========== 生成完整的 32MB SPI‑NOR 镜像 ==========
echo "=== Creating full 32MB SPI‑NOR image ==="
FULL_IMAGE="$OUTPUT_DIR/firmware/SL3000-full-spi-nor-32mb.bin"

dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$FULL_IMAGE"
dd if="$OUTPUT_DIR/atf/BL2.bin" of="$FULL_IMAGE" bs=1 conv=notrunc
dd if="$OUTPUT_DIR/atf/u-boot-env.bin" of="$FULL_IMAGE" bs=1 seek=$((0x100000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/Config.bin" of="$FULL_IMAGE" bs=1 seek=$((0x110000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/Factory.bin" of="$FULL_IMAGE" bs=1 seek=$((0x180000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/FIP.bin" of="$FULL_IMAGE" bs=1 seek=$((0x380000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/firmware.bin" of="$FULL_IMAGE" bs=1 seek=$((0x580000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/Product.bin" of="$FULL_IMAGE" bs=1 seek=$((0x1e80000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/Custom.bin" of="$FULL_IMAGE" bs=1 seek=$((0x1ea0000)) conv=notrunc

echo "✅ Full 32MB SPI‑NOR image created: $FULL_IMAGE"
ls -lh "$FULL_IMAGE"

if cmp -s "$OUTPUT_DIR/atf/Factory.bin" <(dd if=/dev/zero bs=2097152 count=1 2>/dev/null | tr '\000' '\377'); then
    echo "⚠️  WARNING: Factory partition is empty (0xFF). WiFi calibration data missing!"
fi

# ========== 打包 mtk_uartboot ==========
if [ -d "$SOURCE_DIR/mtk_uartboot" ]; then
    cd "$SOURCE_DIR/mtk_uartboot"
    tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
    echo "✅ mtk_uartboot.tar.gz created"
else
    echo "⚠️  mtk_uartboot directory not found, skipping"
fi

echo "✅ Build complete"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
