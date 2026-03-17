#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 路径平铺与环境净化脚本 (V22.0)
# ---------------------------------------------------------

echo "开始执行物理级净化与源码空间重构..."

# 1. 【物理净化】强制抹除 .config 中的 CCACHE 痕迹 (彻底解决编译器找不到报错)
# 这一步会物理扫描并删除所有 CCACHE 相关的配置行，确保编译器走 /usr/bin/gcc
sed -i '/CONFIG_CCACHE/d' .config
echo "# CONFIG_CCACHE is not set" >> .config
echo "CONFIG_CCACHE=n" >> .config

# 2. 补齐物理工具软链接 (防止 flex 执行 m4 失败)
sudo ln -sf /usr/bin/m4 /usr/local/bin/m4 2>/dev/null || true

# 3. 彻底重构 ATF Makefile (对齐种子配置里的 mt7981-sl3000-emmc)
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "物理重写 ATF 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$ATF_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    # 物理平铺：在 Build/Prepare 阶段将子目录 atf/ 内容翻到根目录
    sed -i '/define Build\/Prepare/a \	mv $(PKG_BUILD_DIR)/atf/* $(PKG_BUILD_DIR)/' "$ATF_MK"
    
    # 物理注入零件 ID 定义 (确保与 config 里的 sl3000-emmc 像素级匹配)
    sed -i '/define Device\/mt7981-sl3000-emmc/,/endef/d' "$ATF_MK"
    echo "define Device/mt7981-sl3000-emmc" >> "$ATF_MK"
    echo "  NAME := SL-3000 (eMMC)" >> "$ATF_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$ATF_MK"
    echo "endef" >> "$ATF_MK"
    echo "TARGET_DEVICES += mt7981-sl3000-emmc" >> "$ATF_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 4. 彻底重构 U-Boot Makefile (对应种子配置 mt7981_sl3000_emmc)
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "物理重写 U-Boot 构建逻辑..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$UBOOT_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    # 物理平铺逻辑
    sed -i '/define Build\/Prepare/a \	mv $(PKG_BUILD_DIR)/u-boot/* $(PKG_BUILD_DIR)/' "$UBOOT_MK"
    # 强制修正 ID 命名对齐镜像生成
    sed -i 's/sl3000-emmc/sl3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl3000_emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 5. 镜像生成物理对齐 (确保生成针对 eMMC 的 factory.bin)
IMAGE_MK="target/linux/mediatek/image/mt7981.mk"
if [ -f "$IMAGE_MK" ]; then
    sed -i 's/sl3000-emmc/sl3000-emmc/g' "$IMAGE_MK"
fi
