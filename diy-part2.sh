#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 环境兼容与路径平铺脚本
# 针对：128G eMMC + 内核编译工具链补齐 + 子目录平铺
# ---------------------------------------------------------

echo "执行物理级路径重定向与环境兼容性修正..."

# 1. 物理强制关闭 CCACHE (防止 Actions 环境中 ccache 命令缺失导致内核编译中断)
sed -i 's/CONFIG_CCACHE=y/# CONFIG_CCACHE is not set/g' .config

# 2. 彻底重构 ATF Makefile
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "物理重写 ATF 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$ATF_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    # 物理平铺子目录内容
    sed -i '/define Build\/Prepare/a \	mv $(PKG_BUILD_DIR)/atf/* $(PKG_BUILD_DIR)/' "$ATF_MK"
    # 物理注入零件 ID (匹配种子配置)
    sed -i '/define Device\/mt7981-sl3000-emmc/,/endef/d' "$ATF_MK"
    echo "define Device/mt7981-sl3000-emmc" >> "$ATF_MK"
    echo "  NAME := SL-3000 (eMMC)" >> "$ATF_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$ATF_MK"
    echo "endef" >> "$ATF_MK"
    echo "TARGET_DEVICES += mt7981-sl3000-emmc" >> "$ATF_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 3. 彻底重构 U-Boot Makefile
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "物理重写 U-Boot 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$UBOOT_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    # 物理平铺子目录内容
    sed -i '/define Build\/Prepare/a \	mv $(PKG_BUILD_DIR)/u-boot/* $(PKG_BUILD_DIR)/' "$UBOOT_MK"
    # 物理锁定零件 ID
    sed -i 's/sl3000-emmc/sl3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl3000_emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 4. 物理修正 mt7981.mk (确保救砖包 factory.bin 生成)
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    sed -i 's/sl3000-emmc/sl3000-emmc/g' "$IMAGE_MK"
fi
