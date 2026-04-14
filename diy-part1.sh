#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
CONFIG_DIR="$WORKSPACE/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"

mkdir -p "$OUTPUT_DIR"/{atf,uboot,firmware}

# 检查源码目录
for d in immortalwrt arm-trusted-firmware u-boot; do
    [ -d "$WORKSPACE/$d" ] || { echo "❌ 缺少 $d"; exit 1; }
done

# 准备构建目录
rm -rf "$IMMORTALWRT_BUILD"
cp -r "$WORKSPACE/immortalwrt" "$IMMORTALWRT_BUILD"
cd "$IMMORTALWRT_BUILD"

# 禁用 telephony feed
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 更新 feeds
./scripts/feeds update -a || exit 1
./scripts/feeds install -a || exit 1

# 删除问题包
PROBLEM_PKGS="aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl python-rpds-py python-service-identity python-twisted python-docker python-jsonschema python-jsonschema-specifications python-referencing onionshare-cli onionshare weston wpewebkit libextractor python-bcrypt python-cryptography python-maturin podman ruby-yaml"
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done
rm -rf feeds/video feeds/telephony package/feeds
./scripts/feeds update -i || exit 1
./scripts/feeds install -a || exit 1
make package/symlinks || exit 1

# 复制 DTS（双路径保险）
DTS_OLD="target/linux/mediatek/dts"
DTS_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
mkdir -p "$DTS_OLD" "$DTS_NEW"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_OLD/" || exit 1
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_NEW/" || exit 1

# 追加设备定义到 filogic.mk
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
cat >> "$FILOGIC_MK" << 'EOF'

# SL3000 救砖设备定义
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

# 复制基础配置并强制启用设备
cp -v "$CONFIG_DIR/sl3000-rescue.config" .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config
cat >> .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TARGET_INITRAMFS_COMPRESSION_LZMA=y
EOF

make defconfig
make -j1 V=s oldconfig
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config || { echo "❌ 设备未启用"; exit 1; }

echo "$IMMORTALWRT_BUILD" > "$WORKSPACE/build-dir.txt"
echo "✅ part1 完成"
