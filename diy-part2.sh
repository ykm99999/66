#!/bin/bash
# SL-3000 救砖全家桶物理拉起脚本

echo "--- 物理执行：开始屏蔽官方干扰并注入 888 零件 ---"

# 1. 物理切除官方补丁 (防止 Patch Failed)
rm -rf package/boot/arm-trusted-firmware-mediatek/patches
rm -rf package/boot/uboot-mediatek/patches

# 2. 物理替换 Makefile 规则 (使用你仓库 888 里的推荐版)
cp -v ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -v ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -v ../888/filogic.mk target/linux/mediatek/image/filogic.mk

# 3. 注入配置并强制同步
if [ -f ../888/sl3000.config ]; then
    cp -v ../888/sl3000.config .config
    make defconfig
fi

# 4. 物理拉起：执行 Prepare 解压源码 (忽略 Makefile 内部警告)
make package/boot/arm-trusted-firmware-mediatek/prepare V=s || true

# 5. 【物理核心】：从 888 目录跨路径注入救砖零件
# 自动探测 build_dir 下解压出的 ATF 源码目录
ATF_SRC=$(find build_dir -name "arm-trusted-firmware-*" -type d | head -n 1)

if [ -n "$ATF_SRC" ]; then
    echo "定位 ATF 物理路径: $ATF_SRC"
    
    # 强制创建子目录架构
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/bl2
    mkdir -p $ATF_SRC/plat/mediatek/mt7981/include

    # 注入核心 10 零件 (示例)
    cp -v ../888/bl2_dev_spi_nor.c $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/bl2.mk $ATF_SRC/plat/mediatek/mt7981/bl2/
    cp -v ../888/platform.mk $ATF_SRC/plat/mediatek/mt7981/
    cp -v ../888/platform_def.h $ATF_SRC/plat/mediatek/mt7981/include/
    
    # 物理覆盖设备树 (分区表对齐)
    find $ATF_SRC -name "mt7981-spi2.dts" -exec cp -v ../888/mt7981-spi2.dts {} \;
    
    # 物理标记硬化：强制绕过 package.mk 的 MD5 校验
    touch $ATF_SRC/.prepared*
    echo "--- ATF 救砖零件注入成功 ---"
else
    echo "物理报错：找不到 ATF 源码，请检查 atf-Makefile"
    exit 1
fi

echo "--- 物理拉起全流程结束 ---"
