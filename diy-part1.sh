#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware}

# 验证源码存在
for d in immortalwrt arm-trusted-firmware u-boot mtk_uartboot; do
  if [ ! -d "$SOURCE_DIR/$d" ]; then
    echo "Missing $SOURCE_DIR/$d"
    exit 1
  fi
done

# 准备 ImmortalWrt 构建目录
rm -rf "$WORKSPACE/immortalwrt-build"
cp -r "$SOURCE_DIR/immortalwrt" "$WORKSPACE/immortalwrt-build"
cd "$WORKSPACE/immortalwrt-build"

# 复制 DTS 和配置
mkdir -p target/linux/mediatek/dts
cp "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp "$CONFIG_DIR/sl3000-rescue.config" .config

# 追加设备定义
cat >> target/linux/mediatek/image/filogic.mk << 'EOF'

define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Rescue
  DEVICE_DTS := mt7981b-sl3000-emmc
  SOC := mt7981
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | gzip
  IMAGES := rescue-initramfs-kernel.bin
  IMAGE/rescue-initramfs-kernel.bin := append-kernel
  DEVICE_PACKAGES := uboot-envtools mtd-utils kmod-mtd-rw block-mount kmod-mmc kmod-mmc-mtk kmod-fs-ext4
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
EOF

# 强制启用设备
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" >> .config
echo "CONFIG_TARGET_ROOTFS_INITRAMFS=y" >> .config
make defconfig

echo "$WORKSPACE/immortalwrt-build" > "$WORKSPACE/build-dir.txt"
echo "part1 done"
