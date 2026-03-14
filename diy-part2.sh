#!/bin/bash
# SL-3000 救砖全家桶：物理路径对齐修复脚本

echo "--- 物理执行：清理干扰并开始注入 ---"

# 1. 屏蔽官方干扰
rm -rf package/boot/arm-trusted-firmware-mediatek/patches
rm -rf package/boot/uboot-mediatek/patches

# 2. 注入推荐版 Makefile
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile

# 3. 物理执行 Prepare (解压)
make package/boot/arm-trusted-firmware-mediatek/prepare V=s || true

# 4. 【深度修复】：物理对齐 ATF 源码路径
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位 ATF 路径: $ATF_SRC"
    
    # 检查根目录是否有 Makefile，如果没有，去子目录找并提取
    if [ ! -f "$ATF_SRC/Makefile" ]; then
        echo "警告：根目录缺失 Makefile，尝试从子目录提取..."
        # 假设源码在 atf/ 文件夹里
        SUB_DIR=$(find $ATF_SRC -name "Makefile" -printf '%h\n' | head -n 1)
        if [ -n "$SUB_DIR" ] && [ "$SUB_DIR" != "$ATF_SRC" ]; then
            echo "发现源码实际位置: $SUB_DIR，正在物理提升至根目录..."
            mv $SUB_DIR/* $ATF_SRC/ 2>/dev/null || cp -r $SUB_DIR/* $ATF_SRC/
        fi
    fi

    # 5. 精准注入 888 零件
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/include

    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # 物理覆盖 DTS (使用最稳健的 find 覆盖法)
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
    
    # 强制标记已准备
    touch $ATF_SRC/.prepared*
    echo "--- ATF 路径对齐与零件注入成功 ---"
else
    echo "物理报错：未发现源码目录"
    exit 1
fi
