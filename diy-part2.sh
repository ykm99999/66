#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 路径重构终结脚本 (V16.0)
# 针对：128G eMMC + 子目录源码平铺 + 零件 ID 注入
# ---------------------------------------------------------

echo "执行物理级路径重定向与零件 ID 强制补全..."

# 1. 彻底重构 ATF Makefile
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "物理重写 ATF 构建逻辑..."
    # 物理锁定仓库与分支
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$ATF_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    
    # 【核心操作】物理平铺子目录内容：在解压后，强制将 atf/ 文件夹内的东西移到根目录
    sed -i '/define Build\/Prepare/a \	mv $(PKG_BUILD_DIR)/atf/* $(PKG_BUILD_DIR)/' "$ATF_MK"
    
    # 物理注入零件 ID 定义 (匹配种子配置：mt7981-sl3000-emmc)
    sed -i '/define Device\/mt7981-sl3000-emmc/,/endef/d' "$ATF_MK"
    echo "define Device/mt7981-sl3000-emmc" >> "$ATF_MK"
    echo "  NAME := SL-3000 (eMMC)" >> "$ATF_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$ATF_MK"
    echo "endef" >> "$ATF_MK"
    echo "TARGET_DEVICES += mt7981-sl3000-emmc" >> "$ATF_MK"
    
    # 物理对齐 Tab
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 2. 彻底重构 U-Boot Makefile
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "物理重写 U-Boot 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$UBOOT_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    
    # 【核心操作】物理平铺 u-boot 子目录内容
    sed -i '/define Build\/Prepare/a \	mv $(PKG_BUILD_DIR)/u-boot/* $(PKG_BUILD_DIR)/' "$UBOOT_MK"
    
    # 物理锁定零件 ID 对齐 (与种子配置像素级一致)
    sed -i 's/sl3000-emmc/sl3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl3000_emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 3. 补全 mt7981.mk 救砖镜像链 (128M Factory)
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    echo "物理注入 128M 救砖包定义..."
    sed -i '/define Device\/sl_3000-emmc/,/endef/d' "$IMAGE_MK"
    echo "define Device/sl_3000-emmc" >> "$IMAGE_MK"
    echo "  DEVICE_VENDOR := SL" >> "$IMAGE_MK"
    echo "  DEVICE_MODEL := 3000 eMMC" >> "$IMAGE_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$IMAGE_MK"
    echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> "$IMAGE_MK"
    echo "  DEVICE_PACKAGES := kmod-mmc kmod-mmc-mtk kmod-fs-f2fs kmod-fs-ext4 f2fs-tools" >> "$IMAGE_MK"
    echo "  KERNEL_SIZE := 10240k" >> "$IMAGE_MK"
    echo "  IMAGES := sysupgrade.bin factory.bin" >> "$IMAGE_MK"
    echo "  IMAGE/factory.bin := append-kernel | pad-to \$\$(KERNEL_SIZE) | append-rootfs | pad-to 128M | check-size" >> "$IMAGE_MK"
    echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> "$IMAGE_MK"
    echo "  UBOOT_DEVICE_NAME := mt7981_sl3000_emmc" >> "$IMAGE_MK"
    echo "endef" >> "$IMAGE_MK"
    echo "TARGET_DEVICES += sl_3000-emmc" >> "$IMAGE_MK"
fi
