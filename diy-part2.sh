#!/bin/bash
# =========================================================
# 物理执行：SL-3000 4核心文件强制覆盖脚本
# =========================================================

# 1. 物理覆盖 ATF (确保 DDR4 驱动)
if [ -f "../888/atf-Makefile" ]; then
    cp -f ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
    echo "物理诊断：ATF Makefile 已覆盖。"
fi

# 2. 物理覆盖 U-Boot (确保 NOR 启动灵魂)
if [ -f "../888/uboot-Makefile" ]; then
    cp -f ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
    echo "物理诊断：U-Boot Makefile 已注入。"
fi

# 3. 物理覆盖 Image MK (确保 32MB 拼装逻辑)
if [ -f "../888/filogic.mk" ]; then
    cp -f ../888/filogic.mk target/linux/mediatek/image/filogic.mk
    echo "物理诊断：filogic.mk 组装逻辑已覆盖。"
fi

# 4. 物理对齐设备名与生产开关 (加固项)
echo "CONFIG_PACKAGE_arm-trusted-firmware-mediatek-mt7981-nor-ddr4=y" >> .config
echo "CONFIG_PACKAGE_uboot-mediatek-mt7981_sl3000_nor=y" >> .config

echo "物理定论：救砖全家桶生产环境已锁定。"
