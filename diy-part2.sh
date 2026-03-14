#!/bin/bash
# SL-3000 (MT7981) 物理对齐硬化 - 核心拉起脚本

echo "--- 物理执行：正在注入 888 目录下的 10 个核心补丁 ---"

# 1. 解决交互报错（物理对齐配置种子）
if [ -f ../888/sl3000.config ]; then
    cp -v ../888/sl3000.config .config
    # 物理硬化：强制静默补全配置，防止 Error opening terminal 报错
    make defconfig
fi

# 2. 物理拉起：核心 Makefile 替换 (指挥官就位)
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -v ../888/filogic.mk target/linux/mediatek/image/filogic.mk

# 3. 物理准备：强制提前解压 ATF 源码
# 只有 prepare 之后，build_dir 里才会出现对应的源码目录
make package/boot/arm-trusted-firmware-mediatek/prepare V=s

# 4. 定位 ATF 构建目录并执行核心注入
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位物理源码路径: $ATF_SRC"
    
    # 注入：驱动核心 (Hand)
    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    
    # 注入：编译定义 (Rules)
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    
    # 注入：底层地址定义 (Heart - platform_def.h)
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # 注入：硬件地图 (Map - DTS)
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
    
    echo "--- ATF 物理补丁注入成功 ---"
else
    echo "错误：无法捕捉 ATF 源码路径，请检查代码拉取状态！"
    exit 1
fi

echo "--- 物理拉起全流程结束：链路已闭环 ---"
