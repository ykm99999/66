#!/bin/bash
set -e

ROOT_DIR=$(pwd)
OUTPUT_DIR="$ROOT_DIR/output"
mkdir -p "$OUTPUT_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

echo "=========================================="
echo "Step 1: Build ARM Trusted Firmware (BL31)"
echo "=========================================="
cd "$ROOT_DIR/arm-trusted-firmware"
make PLAT=mt7981 CROSS_COMPILE=$CROSS_COMPILE bl31
cp build/mt7981/release/bl31.bin "$OUTPUT_DIR/"

echo "=========================================="
echo "Step 2: Build U-Boot (BL2 + FIP)"
echo "=========================================="
cd "$ROOT_DIR/u-boot"

# 复制 SL3000 设备树
cp "$ROOT_DIR/888/mt7981b-sl3000-emmc.dts" arch/arm/dts/

# 使用参考板 defconfig
make mt7981_nor_emmc_rfb_defconfig

# 更改设备树名称
sed -i 's/CONFIG_DEFAULT_DEVICE_TREE=.*/CONFIG_DEFAULT_DEVICE_TREE="mt7981b-sl3000-emmc"/' .config

# 应用配置
make olddefconfig

# 编译
make -j$(nproc) BL31="$OUTPUT_DIR/bl31.bin"

cp bl2-emmc-ddr4.bin "$OUTPUT_DIR/"
cp bl31-uboot-emmc-ddr4.fip "$OUTPUT_DIR/"

echo "=========================================="
echo "Step 3: Build ImmortalWrt Kernel"
echo "=========================================="
cd "$ROOT_DIR/immortalwrt"

cp "$ROOT_DIR/888/sl3000.config" .config
cp "$ROOT_DIR/888/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp "$ROOT_DIR/888/mt7981_sl3000.mk" target/linux/mediatek/image/

./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make -j$(nproc) target/linux/compile

ITB_PATH=$(find bin/targets/mediatek/mt7981 -name "*-sysupgrade.itb" | head -1)
if [ -f "$ITB_PATH" ]; then
    cp "$ITB_PATH" "$OUTPUT_DIR/sysupgrade.itb"
    echo "Kernel itb copied to $OUTPUT_DIR/sysupgrade.itb"
else
    echo "ERROR: sysupgrade.itb not found!"
    exit 1
fi

echo "=========================================="
echo "All components built successfully!"
echo "Output directory: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
