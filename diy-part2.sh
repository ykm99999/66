#!/bin/bash

# 1. 物理劫持：在 U-Boot 索引中强制为 SL-3000 开门
# 找到 mt7981_xiaomi_mi-router-wr30u 并在下一行插入目标名
sed -i '/mt7981_xiaomi_mi-router-wr30u/a \\tmt7981_sl3000_nor \\' package/boot/uboot-mediatek/Makefile

# 2. 零件覆盖：覆盖上游 Makefile 生产逻辑
# 注意：我们假设 Actions 运行目录在源码根目录，888 目录在根目录同级或指定路径
cp -f 888/atf-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
cp -f 888/uboot-Makefile package/boot/uboot-mediatek/Makefile
cp -f 888/mt7981.mk target/linux/mediatek/image/mt7981.mk

# 3. 配置注入：将 defconfig 放入 U-Boot 寻找路径
mkdir -p package/boot/uboot-mediatek/files
cp -f 888/mt7981_sl3000_nor_defconfig package/boot/uboot-mediatek/files/

# 4. 网络物理接口定义（保底修复）
# 确保系统启动后 LAN/WAN 顺序正确
sed -i '/sl,3000-emmc/d' target/linux/mediatek/filogic/base-files/etc/board.d/02_network
sed -i '/casat,ar3000m/a \\tsl,3000-emmc)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;' target/linux/mediatek/filogic/base-files/etc/board.d/02_network

echo "物理诊断：SL-3000 救砖生产线环境初始化完成。"
