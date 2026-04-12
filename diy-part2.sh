#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_DIR=$(cat "$WORKSPACE/build-dir.txt")

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# 1. ATF
cd "$SOURCE_DIR/arm-trusted-firmware"
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 BOOT_DEVICE=nor DDR_TYPE=ddr4 DRAM_SIZE=1024 NMBM=1 BOARD=mt7981_bga DEBUG=0 all
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2.bin"
cp build/mt7981/release/bl31.bin "$IMMORTALWRT_DIR/staging_dir/image/bl31.bin"

# 2. fiptool
make fiptool CROSS_COMPILE=
cp tools/fiptool/fiptool "$SOURCE_DIR/u-boot/tools/"

# 3. U-Boot
cd "$SOURCE_DIR/u-boot"
mkdir -p arch/arm/dts
cp "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" arch/arm/dts/
sed -i 's/&usb_phy/\/\/ &usb_phy/' arch/arm/dts/mt7981b-sl3000-emmc.dts
make mt7981_nor_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
echo "CONFIG_ENV_OFFSET=0x200000" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- BL31="$IMMORTALWRT_DIR/staging_dir/image/bl31.bin" -j$(nproc)
cp u-boot.fip "$OUTPUT_DIR/uboot/fip.bin"

# 4. ImmortalWrt 内核
cd "$IMMORTALWRT_DIR"
make -j$(nproc) V=s
KERNEL=$(find bin -name "*initramfs-kernel.bin" | head -1)
cp "$KERNEL" "$OUTPUT_DIR/firmware/kernel.bin"

# 5. 组装 32MB 镜像
FULL_IMG="$OUTPUT_DIR/firmware/SL3000-full-spi-nor-32mb.bin"
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$FULL_IMG"
dd if="$OUTPUT_DIR/atf/bl2.bin" of="$FULL_IMG" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip.bin" of="$FULL_IMG" bs=1 seek=$((0x40000)) conv=notrunc
dd if="$OUTPUT_DIR/firmware/kernel.bin" of="$FULL_IMG" bs=1 seek=$((0x220000)) conv=notrunc
echo "Done: $FULL_IMG"
