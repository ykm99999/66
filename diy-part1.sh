#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"

echo "=== 创建工作目录 ==="
mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware}

echo "=== 检查源码目录 ==="
for d in immortalwrt arm-trusted-firmware u-boot; do
    if [ ! -d "$WORKSPACE/$d" ]; then
        echo "❌ 缺少 $d 源码目录"
        exit 1
    fi
done
echo "✅ 源码目录检查通过"

echo "=== 准备 ImmortalWrt 构建目录 ==="
rm -rf "$WORKSPACE/immortalwrt-build"
cp -r "$WORKSPACE/immortalwrt" "$WORKSPACE/immortalwrt-build"
cd "$WORKSPACE/immortalwrt-build"

echo "=== 复制设备树和配置文件 ==="
mkdir -p target/linux/mediatek/dts
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp -v "$CONFIG_DIR/sl3000-rescue.config" .config

echo "=== 追加设备定义到 filogic.mk ==="
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
                     f2fs-tools e2fsprogs dropbear \
                     kmod-leds-gpio kmod-button-hotplug
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
EOF

echo "=== 强制启用目标设备并精简配置 ==="
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config
cat >> .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TARGET_INITRAMFS_COMPRESSION_LZMA=y
# 禁用所有可能引发依赖问题的包
CONFIG_PACKAGE_luci=n
CONFIG_PACKAGE_luci-base=n
CONFIG_PACKAGE_default-settings=n
CONFIG_PACKAGE_default-settings-chn=n
CONFIG_PACKAGE_dnsmasq=n
CONFIG_PACKAGE_dnsmasq-full=n
CONFIG_PACKAGE_odhcpd=n
CONFIG_PACKAGE_odhcp6c=n
CONFIG_PACKAGE_wpad=n
CONFIG_PACKAGE_wpad-openssl=n
CONFIG_PACKAGE_hostapd=n
CONFIG_PACKAGE_iw=n
CONFIG_PACKAGE_kmod-mt76=n
CONFIG_PACKAGE_kmod-mac80211=n
CONFIG_PACKAGE_kmod-cfg80211=n
CONFIG_PACKAGE_ppp=n
CONFIG_PACKAGE_pppoe=n
CONFIG_PACKAGE_firewall4=n
CONFIG_PACKAGE_netifd=n
EOF

make defconfig

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
    echo "❌ 设备未成功启用"
    exit 1
fi
echo "✅ 设备已启用"

# 记录构建目录路径供 part2 使用
echo "$WORKSPACE/immortalwrt-build" > "$WORKSPACE/build-dir.txt"
echo "=== diy-part1.sh 执行完毕 ==="
