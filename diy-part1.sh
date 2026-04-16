#!/bin/bash
set -euo pipefail

# ========== 延续 1 版：路径与环境变量定义 (原文照抄) ==========
WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

# 溯源诊断：修正用户真实文件名
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 延续 1 版：验证配置文件 (原文照抄) ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/$DTS_NAME" ]; then
    echo "❌ 缺少 $CONFIG_DIR/$DTS_NAME"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# ========== 延续 1 版：准备源码 (原文照抄) ==========
echo "=== Preparing ImmortalWrt Source ==="
if [ ! -d "$SOURCE_DIR/immortalwrt" ]; then
    echo "❌ 物理错误：找不到 $SOURCE_DIR/immortalwrt 目录"
    ls -R $SOURCE_DIR
    exit 1
fi
cp -r $SOURCE_DIR/immortalwrt/. $IMMORTALWRT_BUILD/
cd $IMMORTALWRT_BUILD

echo "$IMMORTALWRT_BUILD" > $WORKSPACE/build-dir.txt

# ========== V2 物理修复注入：同步 Feeds 前清理内存补丁 ==========
echo "=== V2 物理修复：清理内存限制补丁 ==="
# 移除所有强行限制 256M/512M 的 Patch，为 1GB DDR4 扫清障碍
find target/linux/mediatek/patches-6.6/ -name "*mt7981-256m-dram*" -delete
find target/linux/mediatek/patches-6.6/ -name "*mt7981-512m-dram*" -delete

# ========== 延续 1 版：同步 Feeds (原文照抄) ==========
./scripts/feeds update -a
./scripts/feeds install -a

# ========== 延续 1 版：注入 DTS 与设备定义 (原文照抄并修正定义) ==========
cp -v $CONFIG_DIR/$DTS_NAME $DTS_PATH_OLD/
mkdir -p $DTS_PATH_NEW
cp -v $CONFIG_DIR/$DTS_NAME $DTS_PATH_NEW/

cat >> $FILOGIC_MK << 'EOF'

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC
  DEVICE_DTS := mt7981b-sl3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_DRAM_SIZE := 1024M
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF

# ========== V2 物理修复注入：修改底层 Bootloader 源码 (200MHz/1G) ==========
echo "=== V2 物理修复：锁定底层 Bootloader 参数 ==="
# 修复串口乱码 (40M -> 200M)
UBOOT_INC="package/boot/uboot-mtk/src/include/configs/mt7981.h"
if [ -f "$UBOOT_INC" ]; then
    sed -i 's/#define CFG_SYS_NS16550_CLK.*/#define CFG_SYS_NS16550_CLK 200000000/g' "$UBOOT_INC"
fi

# 修复 1G 内存返回与 256K 偏移
ATF_EMICFG="package/boot/arm-trusted-firmware-mtk/src/plat/mediatek/mt7981/drivers/dram/emicfg.c"
ATF_PLAT_DEF="package/boot/arm-trusted-firmware-mtk/src/plat/mediatek/mt7981/include/platform_def.h"
if [ -f "$ATF_EMICFG" ]; then
    sed -i 's/return 0x20000000/return 0x40000000/g' "$ATF_EMICFG"
fi
if [ -f "$ATF_PLAT_DEF" ]; then
    sed -i '/#define FLASH_FIP_BASE/d' "$ATF_PLAT_DEF"
    echo "#define FLASH_FIP_BASE (0x40000)" >> "$ATF_PLAT_DEF"
fi

# ========== 延续 1 版：生成配置 (原文照抄) ==========
cp -v $CONFIG_DIR/sl3000.config .config
make defconfig
