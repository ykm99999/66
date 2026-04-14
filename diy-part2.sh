#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_DIR=$(cat "$WORKSPACE/build-dir.txt")

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware}
mkdir -p "$IMMORTALWRT_DIR/staging_dir/image"

# 1. ATF
cd "$WORKSPACE/arm-trusted-firmware"
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 BOOT_DEVICE=nor DDR_TYPE=ddr4 DRAM_SIZE=1024 NMBM=1 BOARD=mt7981_bga DEBUG=0 all
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2.bin"
cp -v build/mt7981/release/bl31.bin "$IMMORTALWRT_DIR/staging_dir/image/bl31.bin"

# 2. fiptool
make fiptool CROSS_COMPILE=
mkdir -p "$WORKSPACE/u-boot/tools"
cp -v tools/fiptool/fiptool "$WORKSPACE/u-boot/tools/"

# 3. U-Boot
cd "$WORKSPACE/u-boot"
mkdir -p arch/arm/dts
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" arch/arm/dts/
sed -i 's/&usb_phy/\/\/ &usb_phy/' arch/arm/dts/mt7981b-sl3000-emmc.dts
sed -i 's/&xhci/\/\/ &xhci/' arch/arm/dts/mt7981b-sl3000-emmc.dts

make mt7981_nor_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
echo "CONFIG_ENV_OFFSET=0x200000" >> .config
echo "CONFIG_ENV_SIZE=0x20000" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- BL31="$IMMORTALWRT_DIR/staging_dir/image/bl31.bin" -j$(nproc)

[ ! -f u-boot.fip ] && tools/fiptool create --soc-fw "$IMMORTALWRT_DIR/staging_dir/image/bl31.bin" --nt-fw u-boot.bin u-boot.fip
cp -v u-boot.fip "$OUTPUT_DIR/uboot/fip.bin"

# 4. 编译 initramfs 内核
cd "$IMMORTALWRT_DIR"
make -j$(nproc) toolchain/install
make -j$(nproc) target/linux/compile

KERNEL_DIR=$(find build_dir -maxdepth 3 -type d -path "*/target-aarch64_cortex-a53_musl/linux-*" | head -1)
[ -n "$KERNEL_DIR" ] || { echo "❌ 未找到内核源码目录"; exit 1; }
cd "$KERNEL_DIR"

# 确保内核编译环境就绪
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- prepare scripts
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image
gzip -9 -c arch/arm64/boot/Image > arch/arm64/boot/Image.gz
cp -v arch/arm64/boot/Image.gz "$OUTPUT_DIR/firmware/kernel.bin"

# 5. 组装完整 32MB SPI 镜像
FULL_IMG="$OUTPUT_DIR/firmware/SL3000-full-spi-nor-32mb.bin"
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$FULL_IMG"
dd if="$OUTPUT_DIR/atf/bl2.bin" of="$FULL_IMG" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip.bin" of="$FULL_IMG" bs=1 seek=$((0x40000)) conv=notrunc
dd if="$OUTPUT_DIR/firmware/kernel.bin" of="$FULL_IMG" bs=1 seek=$((0x220000)) conv=notrunc

echo "✅ 构建成功"
ls -lh "$OUTPUT_DIR/firmware/"
