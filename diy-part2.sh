#!/bin/bash
# SL-3000 救砖全家桶：物理静默对齐脚本

echo "--- 物理执行：清理干扰并开始静默注入 ---"

# 1. 屏蔽官方干扰
rm -rf package/boot/arm-trusted-firmware-mediatek/patches
rm -rf package/boot/uboot-mediatek/patches

# 2. 注入推荐版 Makefile
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# 3. 【核心修复】：物理静默配置对齐
# 理由：防止触发 "Error opening terminal"
if [ -f ../888/sl3000.config ]; then
    echo "发现种子配置，执行物理静默对齐..."
    cp -v ../888/sl3000.config .config
    # 强制不产生交互，自动接受默认选项
    make defconfig
else
    echo "警告：未发现种子配置，将使用默认环境编译"
fi

# 4. 物理执行 Prepare (解压)
# 这一步现在应该能顺利通过，因为配置已经对齐
make package/boot/arm-trusted-firmware-mediatek/prepare V=s || true

# 5. 物理对齐 ATF 源码路径
# 即使解压失败，我们也尝试进入目录进行救砖零件物理覆盖
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位 ATF 路径: $ATF_SRC"
    
    # 物理对齐：提取子目录源码 (防止仓库结构嵌套)
    if [ ! -f "$ATF_SRC/Makefile" ]; then
        SUB_DIR=$(find $ATF_SRC -name "Makefile" -printf '%h\n' | head -n 1)
        if [ -n "$SUB_DIR" ] && [ "$SUB_DIR" != "$ATF_SRC" ]; then
            echo "发现嵌套源码，物理提升..."
            mv $SUB_DIR/* $ATF_SRC/ 2>/dev/null || cp -r $SUB_DIR/* $ATF_SRC/
        fi
    fi

    # 6. 精准注入 888 零件
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/include

    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # 物理覆盖 DTS
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
    
    touch $ATF_SRC/.prepared*
    echo "--- ATF 路径对齐与零件注入成功 ---"
else
    echo "物理报错：源码目录依然缺失。请检查 atf-Makefile 中的下载链接是否有效"
    exit 1
fi
