#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
#  diy-part1.sh - 环境准备与源码获取
# ------------------------------------------------------------

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"

echo "=== 创建工作目录 ==="
mkdir -p "$SOURCE_DIR" "$OUTPUT_DIR"/{atf,uboot,firmware}

# -------------------- 克隆 ImmortalWrt (MT798x 专用分支) --------------------
echo "=== 克隆 ImmortalWrt 源码 ==="
if [ ! -d "$SOURCE_DIR/immortalwrt" ]; then
    git clone --depth=1 -b openwrt-24.10 https://github.com/hanwckf/immortalwrt-mt798x.git "$SOURCE_DIR/immortalwrt"
else
    echo "ImmortalWrt 源码已存在，跳过克隆"
fi

# -------------------- 克隆 ATF (ARM Trusted Firmware) --------------------
echo "=== 克隆 ATF 源码 ==="
if [ ! -d "$SOURCE_DIR/arm-trusted-firmware" ]; then
    git clone --depth=1 https://github.com/mtk-openwrt/arm-trusted-firmware.git "$SOURCE_DIR/arm-trusted-firmware"
else
    echo "ATF 源码已存在，跳过克隆"
fi

# -------------------- 克隆 U-Boot --------------------
echo "=== 克隆 U-Boot 源码 ==="
if [ ! -d "$SOURCE_DIR/u-boot" ]; then
    git clone --depth=1 https://github.com/mtk-openwrt/u-boot.git "$SOURCE_DIR/u-boot"
else
    echo "U-Boot 源码已存在，跳过克隆"
fi

# -------------------- 克隆 mtk_uartboot (可选) --------------------
echo "=== 克隆 mtk_uartboot 工具 ==="
if [ ! -d "$SOURCE_DIR/mtk_uartboot" ]; then
    git clone --depth=1 https://github.com/981213/mtk_uartboot.git "$SOURCE_DIR/mtk_uartboot"
else
    echo "mtk_uartboot 已存在，跳过克隆"
fi

# -------------------- 准备 ImmortalWrt 构建目录 --------------------
echo "=== 准备 ImmortalWrt 构建目录 ==="
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
rm -rf "$IMMORTALWRT_BUILD"
cp -r "$SOURCE_DIR/immortalwrt" "$IMMORTALWRT_BUILD"

# -------------------- 集成设备配置文件 --------------------
echo "=== 集成设备配置文件 ==="
cd "$IMMORTALWRT_BUILD"

# 复制设备树
mkdir -p target/linux/mediatek/dts
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/

# 复制基础配置
cp -v "$CONFIG_DIR/sl3000-rescue.config" .config

# 将设备定义追加到 filogic.mk
cat >> target/linux/mediatek/image/filogic.mk << 'EOF'

# ---------- 司络 SL3000 SPI NOR 救援模式 ----------
define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Rescue (1GB DDR4 / 32MB NOR)
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-nor

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | gzip

  IMAGES := rescue-initramfs-kernel.bin
  IMAGE/rescue-initramfs-kernel.bin := append-kernel

  BLOCKSIZE := 128k
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear \
    kmod-leds-gpio kmod-button-hotplug
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
EOF

# 强制启用设备
sed -i '/CONFIG_TARGET_mediatek/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic/d' .config
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_/d' .config

cat >> .config << 'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_PACKAGE_gdisk=y
EOF

make defconfig

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_mt7981_sl3000_spi_rescue=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 救砖设备已启用"

# 记录构建目录路径供 part2 使用
echo "$IMMORTALWRT_BUILD" > "$WORKSPACE/build-dir.txt"
echo "✅ part1 完成，构建目录：$IMMORTALWRT_BUILD"
