#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware}

# 检查源码目录
for d in immortalwrt arm-trusted-firmware u-boot; do
    if [ ! -d "$WORKSPACE/$d" ]; then
        echo "❌ 缺少 $d 源码目录"
        exit 1
    fi
done

# 准备 ImmortalWrt 构建目录
rm -rf "$WORKSPACE/immortalwrt-build"
cp -r "$WORKSPACE/immortalwrt" "$WORKSPACE/immortalwrt-build"
cd "$WORKSPACE/immortalwrt-build"

# 删除所有可能引发依赖问题的包目录
rm -rf package/emortal \
       feeds/luci \
       feeds/packages/net/samba4 \
       package/kernel/mt76 \
       package/utils/busybox \
       package/utils/policycoreutils \
       package/network/services/lldpd \
       package/boot/kexec-tools \
       package/utils/audit \
       package/system/refpolicy \
       package/system/selinux-policy \
       package/base-files \
       package/libs/libsemanage

# 复制 DTS 和配置
mkdir -p target/linux/mediatek/dts
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp -v "$CONFIG_DIR/sl3000-rescue.config" .config

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
  DEVICE_PACKAGES := uboot-envtools mtd-utils kmod-mtd-rw block-mount \
                     kmod-mmc kmod-mmc-mtk kmod-fs-ext4 kmod-fs-f2fs \
                     f2fs-tools e2fsprogs dropbear
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
EOF

# 强制启用目标设备并精简配置
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config
cat >> .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TARGET_INITRAMFS_COMPRESSION_LZMA=y
CONFIG_PACKAGE_luci=n
CONFIG_PACKAGE_default-settings=n
CONFIG_PACKAGE_kmod-mt76=n
CONFIG_PACKAGE_kmod-mac80211=n
CONFIG_PACKAGE_wpad=n
EOF

make defconfig

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
    echo "❌ 设备未启用"
    exit 1
fi

echo "$WORKSPACE/immortalwrt-build" > "$WORKSPACE/build-dir.txt"
echo "part1 完成"
