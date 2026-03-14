#!/bin/bash
# SL-3000 (MT7981) 物理硬化脚本

echo "--- 物理执行：开始注入补丁 ---"

# 1. 解决交互报错
if [ -f ../888/sl3000.config ]; then
    cp -v ../888/sl3000.config .config
    make defconfig
fi

# 2. 物理替换 Makefile (指挥官拉起)
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -v ../888/filogic.mk target/linux/mediatek/image/filogic.mk

# 【最小物理修补】：物理清空所有不相关的官方补丁
# 这一行会物理删除整个 patches 文件夹，确保 prepare 阶段不会因为补丁冲突报错
rm -rf package/boot/arm-trusted-firmware-mediatek/patches

# 3. 强制准备源码 (跳过补丁应用环节)
make package/boot/arm-trusted-firmware-mediatek/prepare V=s

# 4. 精准路径注入
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位 ATF 源码: $ATF_SRC"
    
    # 物理开路
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/include

    # 零件复刻覆盖 (10个零件中的核心注入)
    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # DTS 覆盖
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
fi

echo "--- 物理拉起全流程结束 ---"
