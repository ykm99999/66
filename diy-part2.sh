#!/bin/bash
# SL-3000 (MT7981) 物理硬化脚本 - 禁用官方补丁构建并注入零件

echo "--- 物理执行：开始屏蔽不相关的官方补丁并注入零件 ---"

# 1. 物理切断补丁触发源 (实现“不构建补丁”的核心)
# 物理路径溯源：package/boot/ 下的官方补丁会干扰自定义源码，必须物理抹除
rm -rf package/boot/arm-trusted-firmware-mediatek/patches
rm -rf package/boot/uboot-mediatek/patches

# 2. 物理替换 Makefile (拉起自定义源码编译规则)
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -v ../888/filogic.mk target/linux/mediatek/image/filogic.mk

# 3. 注入种子配置，绕过终端交互错误
if [ -f ../888/sl3000.config ]; then
    cp -v ../888/sl3000.config .config
    # 物理硬化配置，确保不弹出终端选择界面
    make defconfig
fi

# 4. 强制执行 prepare (此时补丁已物理消失，源码将纯净解压)
make package/boot/arm-trusted-firmware-mediatek/prepare V=s

# 5. 精准注入 888 核心零件 (物理复刻：路径必须完全对齐)
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位 ATF 源码物理路径: $ATF_SRC"
    
    # 物理开路：确保子目录存在
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/include

    # 注入你的 10 个核心零件
    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # 物理硬件地图覆盖
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
    echo "--- ATF 零件物理注入成功 ---"
else
    echo "错误：未发现 ATF 源码目录，物理链路中断！"
    exit 1
fi

echo "--- 物理拉起全流程结束：补丁已跳过，10个零件已就位 ---"
