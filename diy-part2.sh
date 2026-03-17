#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：全链路名称自动对齐修复脚本 (禁用 EOF 版)
# ---------------------------------------------------------

echo "开始全链路像素级对齐自检 (禁用 EOF 模式)..."

# 1. 物理重构 U-Boot 依赖
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "正在物理修正 U-Boot 依赖路径..."
    sed -i 's/sl3000-emmc/sl_3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl-3000-emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
    sed -i 's/Include /include /g' "$UBOOT_MK"
fi

# 2. 物理修复 mt7981.mk 救砖全家桶
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    echo "正在物理注入救砖逻辑到 mt7981.mk..."
    # 物理清除原有旧定义
    sed -i '/define Device\/sl_3000-emmc/,/endef/d' "$IMAGE_MK"
    
    # 使用 echo 物理追加，彻底弃用 EOF
    echo "" >> "$IMAGE_MK"
    echo "define Device/sl_3000-emmc" >> "$IMAGE_MK"
    echo "  DEVICE_VENDOR := SL" >> "$IMAGE_MK"
    echo "  DEVICE_MODEL := 3000 eMMC" >> "$IMAGE_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$IMAGE_MK"
    echo "  DEVICE_DTS_DIR := \$(DTS_DIR)/mediatek" >> "$IMAGE_MK"
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

# 3. 物理刷新索引
rm -rf tmp
./scripts/feeds update -a
./scripts/feeds install -a

echo "物理全链路名称对齐完成：sl_3000-emmc 标准已锁定。"
