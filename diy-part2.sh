#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 路径重构终结脚本 (V12.0)
# 针对：子目录源码结构 + 零件 ID 注入
# ---------------------------------------------------------

echo "开始物理级依赖重构与子目录适配..."

# 1. 彻底重构 ATF Makefile (解决 dependency missing)
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "物理重写 ATF 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$ATF_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    # 强制让系统去 atf 子目录编译
    sed -i '/PKG_BUILD_DIR:=/c\PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)/atf' "$ATF_MK"
    # 物理注入零件 ID 定义
    sed -i '/define Device\/mt7981-sl_3000-emmc/,/endef/d' "$ATF_MK"
    echo "define Device/mt7981-sl_3000-emmc" >> "$ATF_MK"
    echo "  NAME := SL-3000 (eMMC)" >> "$ATF_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$ATF_MK"
    echo "endef" >> "$ATF_MK"
    echo "TARGET_DEVICES += mt7981-sl_3000-emmc" >> "$ATF_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 2. 彻底重构 U-Boot Makefile
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "物理重写 U-Boot 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$UBOOT_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    # 强制让系统去 u-boot 子目录编译
    sed -i '/PKG_BUILD_DIR:=/c\PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)/u-boot' "$UBOOT_MK"
    # 物理锁定零件 ID 对齐
    sed -i 's/sl3000-emmc/sl_3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl-3000-emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 3. 补全 mt7981.mk 镜像生成链
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    sed -i '/define Device\/sl_3000-emmc/,/endef/d' "$IMAGE_MK"
    echo "define Device/sl_3000-emmc" >> "$IMAGE_MK"
    echo "  DEVICE_VENDOR := SL" >> "$IMAGE_MK"
    echo "  DEVICE_MODEL := 3000 eMMC" >> "$IMAGE_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$IMAGE_MK"
    echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> "$IMAGE_MK"
    echo "  DEVICE_PACKAGES := \$(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc" >> "$IMAGE_MK"
    echo "  KERNEL_SIZE := 10240k" >> "$IMAGE_MK"
    echo "  IMAGES := sysupgrade.bin factory.bin" >> "$IMAGE_MK"
    echo "  IMAGE/factory.bin := append-kernel | pad-to \$\$(KERNEL_SIZE) | append-rootfs | pad-to 128M | check-size" >> "$IMAGE_MK"
    echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> "$IMAGE_MK"
    echo "  UBOOT_DEVICE_NAME := mt7981_sl_3000_emmc" >> "$IMAGE_MK"
    echo "endef" >> "$IMAGE_MK"
    echo "TARGET_DEVICES += sl_3000-emmc" >> "$IMAGE_MK"
fi
