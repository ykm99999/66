#!/bin/bash

# 1. 物理劫持：强行在 U-Boot 索引中落户
sed -i '/mt7981_xiaomi_mi-router-wr30u/a \\tmt7981_sl3000_nor \\' package/boot/uboot-mediatek/Makefile

# 2. 零件覆盖：覆盖上游 Makefile 及镜像生成逻辑
[ -f "../888/atf-Makefile" ] && cp -f ../888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
[ -f "../888/uboot-Makefile" ] && cp -f ../888/uboot-Makefile package/boot/uboot-mediatek/Makefile
[ -f "../888/mt7981.mk" ] && cp -f ../888/mt7981.mk target/linux/mediatek/image/mt7981.mk

# 3. 注入图纸：将 defconfig 放入编译寻找路径
mkdir -p package/boot/uboot-mediatek/files
cp -f ../888/mt7981_sl3000_nor_defconfig package/boot/uboot-mediatek/files/

# 4. DTS 强化：确保 eMMC 版 DTS 存在且被内核编译
DTS_DIR="target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
if [ -f "../888/mt7981-sl-3000-emmc.dts" ]; then
    cp -f ../888/mt7981-sl-3000-emmc.dts $DTS_DIR/
fi

# 5. 网络定义：修复 WAN/LAN 物理接口顺序
sed -i '/sl,3000-emmc/d' target/linux/mediatek/filogic/base-files/etc/board.d/02_network
sed -i '/casat,ar3000m/a \\tsl,3000-emmc)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;' target/linux/mediatek/filogic/base-files/etc/board.d/02_network
