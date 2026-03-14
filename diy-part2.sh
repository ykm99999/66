#!/bin/bash
# SL-3000 (MT7981) 物理硬化脚本 - 适配特定源码仓库结构

echo "--- 物理执行：开始注入补丁 ---"

# 1. 强制注入配置，绕过交互报错
if [ -f ../888/sl3000.config ]; then
    cp -v ../888/sl3000.config .config
    make defconfig
fi

# 2. 物理替换 Makefile
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -v ../888/filogic.mk target/linux/mediatek/image/filogic.mk

# 3. 强制提前解压
make package/boot/arm-trusted-firmware-mediatek/prepare V=s

# 4. 精准路径注入 (基于你提供的仓库结构)
# 寻找源码根目录
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位 ATF 源码: $ATF_SRC"
    
    # 物理校准：在你的仓库里，路径是 plat/mediatek/mt7981/
    # 我们使用 mkdir -p 确保万无一失
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/include

    # 注入零件
    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # DTS 注入：针对你的 atf 仓库，fdts 目录在根部
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
fi

echo "--- 物理拉起全流程结束 ---"
