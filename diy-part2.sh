#!/bin/bash
# ---------------------------------------------------------
# 物理执行三准则：SL3000 子目录物理重构脚本 (V10.0 终极版)
# 针对：u-boot/atf 位于子目录 + 禁用 EOF + 零件 ID 注入
# ---------------------------------------------------------

# 1. 物理位置纠偏
[ -d "openwrt" ] && cd openwrt || { echo "物理断链"; exit 1; }

echo "开始物理级依赖重构与子目录适配..."

# 2. 物理修复 ATF Makefile 逻辑
ATF_MK="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_MK" ]; then
    echo "重定向 ATF 源码源并锁定 ID..."
    # 锁定物理仓库和分支
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$ATF_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$ATF_MK"
    
    # 物理注入：在编译解压后，强制进入 atf 子目录执行（或将内容移出）
    # 这里我们通过修改构建指令，确保编译器在 atf/ 目录下寻找 Makefile
    sed -i 's/HOST_BUILD_DIR)/HOST_BUILD_DIR)\/atf/g' "$ATF_MK"
    
    # 物理注入零件 ID 定义，解决“依赖不存在”报错
    sed -i '/define Device\/mt7981-sl_3000-emmc/,/endef/d' "$ATF_MK"
    echo "define Device/mt7981-sl_3000-emmc" >> "$ATF_MK"
    echo "  NAME := SL-3000 (eMMC)" >> "$ATF_MK"
    echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$ATF_MK"
    echo "endef" >> "$ATF_MK"
    echo "TARGET_DEVICES += mt7981-sl_3000-emmc" >> "$ATF_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_MK"
fi

# 3. 物理修复 U-Boot Makefile 逻辑
UBOOT_MK="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MK" ]; then
    echo "重定向 U-Boot 源码源并适配子目录..."
    sed -i 's|PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://github.com/ykm888/66.git|g' "$UBOOT_MK"
    sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=sl3000-clean-source/g' "$UBOOT_MK"
    
    # 物理注入：让 U-Boot 构建进入 u-boot 子目录
    sed -i 's/BUILD_DIR)/BUILD_DIR)\/u-boot/g' "$UBOOT_MK"
    
    # 物理对齐零件 ID 请求
    sed -i 's/sl3000-emmc/sl_3000-emmc/g' "$UBOOT_MK"
    sed -i 's/mt7981_sl3000_emmc/mt7981_sl-3000-emmc/g' "$UBOOT_MK"
    sed -i 's/^[[:space:]]\+/\t/g' "$UBOOT_MK"
fi

# 4. 物理清理 Feeds 并强制重置索引
rm -rf tmp
./scripts/feeds update -a
./scripts/feeds install -a

echo "自愈完成。已锁定零件 ID 并适配仓库子目录结构。"
