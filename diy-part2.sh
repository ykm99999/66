#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 全链路自愈脚本 (禁用 EOF + 强制依赖补全)
# ---------------------------------------------------------

# 1. 物理位置纠偏
[ -d "openwrt" ] && cd openwrt || { echo "物理断链"; exit 1; }

echo "开始执行像素级依赖重构..."

# 2. 物理重构 ATF Makefile (核心修复：确保 ATF 零件名与 U-Boot 请求一致)
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "物理强制补全 ATF 编译目标..."
    # 锁定分支
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    # 强制物理注入 ATF 设备定义 (针对 sl_3000-emmc)
    # 先清理可能存在的冲突定义
    sed -i '/define Device\/mt7981-sl_3000-emmc/,/endef/d' "$ATF_MK"
    sed -i '/TARGET_DEVICES += mt7981-sl_3000-emmc/d' "$ATF_MK"
    
    # 物理追加 ATF 目标，确保 U-Boot 能找到这个依赖
    echo "define Device/mt7981-sl_3000-emmc" >> "$ATF_MK"
    echo "  NAME := SL-3000 (eMMC)" >> "$ATF_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$ATF_MK"
    echo "endef" >> "$ATF_MK"
    echo "TARGET_DEVICES += mt7981-sl_3000-emmc" >> "$ATF_MK"
    
    # 修复缩进
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 3. 物理重构 U-Boot Makefile
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "物理对齐 U-Boot 零件名称..."
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    # 确保 U-Boot 请求的 ATF 依赖名与上面 ATF 定义的完全一致
    sed -i 's/sl3000-emmc/sl_3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl-3000-emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 4. 物理注入 mt7981.mk 镜像定义
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    echo "注入镜像生成链..."
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

# 5. 强制物理刷新 Feeds
rm -rf tmp
./scripts/feeds update -a
./scripts/feeds install -a

echo "依赖补全完成。现在开始生成 config。"
