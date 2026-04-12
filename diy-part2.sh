#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_DIR=$(cat "$WORKSPACE/build-dir.txt")

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

echo "=== 1. 编译 ATF (BL2/BL31) ==="
cd "$WORKSPACE/arm-trusted-firmware"
make clean
make CROSS_COMPILE=aarch64-linux-gnu- \
     PLAT=mt7981 \
     BOOT_DEVICE=nor \
     DDR_TYPE=ddr4 \
     DRAM_SIZE=1024 \
     NMBM=1 \
     BOARD=mt7981_bga \
     DEBUG=0 \
     all
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2.bin"
cp -v build/mt7981/release/bl31.bin "$IMMORTALWRT_DIR/staging_dir/image/bl31.bin"

echo "=== 2. 编译 fiptool ==="
make fiptool CROSS_COMPILE=
cp -v tools/fiptool/fiptool "$WORKSPACE/u-boot/tools/"

echo "=== 3. 编译 U-Boot ==="
cd "$WORKSPACE/u-boot"
mkdir -p arch/arm/dts
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" arch/arm/dts/
# 禁用 USB 节点（避免编译警告）
sed -i 's/&usb_phy/\/\/ &usb_phy/' arch/arm/dts/mt7981b-sl3000-emmc.dts
sed -i 's/&xhci/\/\/ &xhci/' arch/arm/dts/mt7981b-sl3000-emmc.dts

make mt7981_nor_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
echo "CONFIG_ENV_OFFSET=0x200000" >> .config
echo "CONFIG_ENV_SIZE=0x20000" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- BL31="$IMMORTALWRT_DIR/staging_dir/image/bl31.bin" -j$(nproc)
cp -v u-boot.fip "$OUTPUT_DIR/uboot/fip.bin"

echo "=== 4. 编译 ImmortalWrt 内核 (initramfs) ==="
cd "$IMMORTALWRT_DIR"
make -j$(nproc) V=s
KERNEL=$(find bin -name "*initramfs-kernel.bin" | head -1)
if [ -z "$KERNEL" ]; then
    echo "❌ 未找到 initramfs 内核"
    exit 1
fi
cp -v "$KERNEL" "$OUTPUT_DIR/firmware/kernel.bin"

echo "=== 5. 组装完整 32MB SPI NOR 镜像 ==="
FULL_IMG="$OUTPUT_DIR/firmware/SL3000-full-spi-nor-32mb.bin"
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$FULL_IMG"
dd if="$OUTPUT_DIR/atf/bl2.bin" of="$FULL_IMG" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip.bin" of="$FULL_IMG" bs=1 seek=$((0x40000)) conv=notrunc
dd if="$OUTPUT_DIR/firmware/kernel.bin" of="$FULL_IMG" bs=1 seek=$((0x220000)) conv=notrunc

# 可选：复制 mtk_uartboot 工具
if [ -d "$WORKSPACE/mtk_uartboot" ]; then
    cp -r "$WORKSPACE/mtk_uartboot" "$OUTPUT_DIR/"
fi

echo "=== 构建完成 ==="
ls -lh "$OUTPUT_DIR/firmware/"
