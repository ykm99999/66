#!/bin/bash
# SL-3000 救砖全家桶：全链路物理对齐脚本

echo "--- 物理执行：开始全链路救砖零件注入 ---"

# 1. 屏蔽官方干扰 (防止补丁冲突)
rm -rf package/boot/arm-trusted-firmware-mediatek/patches
rm -rf package/boot/uboot-mediatek/patches

# 2. 注入推荐版 Makefile (从 888 目录提取)
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# 3. 系统级配置对齐
if [ -f ../888/sl3000.config ]; then
    cp -v ../888/sl3000.config .config
    make defconfig
fi

# 4. 【ATF 物理注入】
make package/boot/arm-trusted-firmware-mediatek/prepare V=s || true
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)
if [ -n "$ATF_SRC" ]; then
    echo "注入 ATF 零件至: $ATF_SRC"
    # 物理提升 (处理嵌套)
    if [ ! -f "$ATF_SRC/Makefile" ]; then
        SUB=$(find $ATF_SRC -name "Makefile" -printf '%h\n' | head -n 1)
        [ -n "$SUB" ] && mv $SUB/* $ATF_SRC/
    fi
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
    touch $ATF_SRC/.prepared*
fi

# 5. 【U-Boot 物理注入】
make package/boot/uboot-mediatek/prepare V=s || true
UBOOT_SRC=$(find build_dir -name "uboot-mediatek-*" -type d | head -n 1)
if [ -n "$UBOOT_SRC" ]; then
    echo "注入 U-Boot 零件至: $UBOOT_SRC"
    # 物理提升 (处理嵌套)
    if [ ! -f "$UBOOT_SRC/Makefile" ]; then
        SUB=$(find $UBOOT_SRC -name "Makefile" -printf '%h\n' | head -n 1)
        [ -n "$SUB" ] && mv $SUB/* $UBOOT_SRC/
    fi
    # 注入 1MB 偏移的专属 defconfig
    mkdir -p $UBOOT_SRC/configs
    cp -v ../888/mt7981_sl3000_defconfig $UBOOT_SRC/configs/
    
    # 物理补位：U-Boot DTS (防止 Error 1)
    mkdir -p $UBOOT_SRC/arch/arm/dts/
    # 尝试寻找并覆盖，若 888 有专版则覆盖，否则沿用源码
    [ -f ../888/mt7981-sl3000.dts ] && cp -v ../888/mt7981-sl3000.dts $UBOOT_SRC/arch/arm/dts/
    
    touch $UBOOT_SRC/.prepared*
fi

echo "--- 零件注入成功：物理链路已闭环 ---"
