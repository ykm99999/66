#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 全链路自愈脚本 (V7.0 终极版)
# 针对：双仓库关联 + 禁用 EOF + 源码分支强制锁定
# ---------------------------------------------------------

# 1. 物理坐标纠偏：进入 Action 下载的源码子目录
[ -d "openwrt" ] && cd openwrt || { echo "物理断链：找不到 openwrt 目录"; exit 1; }

echo "开始物理像素级校准..."

# 2. 物理修复 ATF Makefile (锁定 sl3000-clean-source 分支)
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "校准 ATF 物理源码源至 sl3000-clean-source..."
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    # 修复可能存在的名称偏差
    sed -i 's/mt7981-sl3000-emmc/mt7981-sl_3000-emmc/g' "$ATF_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 3. 物理修复 U-Boot Makefile (锁定 sl3000-clean-source 分支)
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "校准 U-Boot 物理源码源至 sl3000-clean-source..."
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    sed -i 's/sl3000-emmc/sl_3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl-3000-emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 4. 物理注入 mt7981.mk 救砖定义 (彻底禁用 EOF，改用逐行 echo)
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    echo "物理注入 eMMC 救砖全家桶镜像链..."
    # 清理底层源中不完整的定义
    sed -i '/define Device\/sl_3000-emmc/,/endef/d' "$IMAGE_MK"
    
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

# 5. 物理重载 Feeds 索引 (确保新定义的设备被系统识别)
rm -rf tmp
./scripts/feeds update -a
./scripts/feeds install -a

echo "全链路物理自愈完成。名称锁定：sl_3000-emmc"
