#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#

# --- 1. 物理源注入 (成功案例插件) ---
# 添加 helloworld 插件源
echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
# 如果需要 Passwall，取消下一行的注释
# echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall' >>feeds.conf.default

# --- 2. 物理依赖预修补 (针对 MT7981 系列) ---
# 某些源码库中可能会有重复的 Makefile 导致编译冲突
# 执行物理清理，确保后续 diy-part2.sh 注入的配置是全局唯一的
rm -rf package/boot/uboot-mediatek
rm -rf package/boot/arm-trusted-firmware-mediatek

# --- 3. 物理内核版本对齐 (可选) ---
# 如果你需要锁定特定的内核版本，可以在这里执行 sed 修改
# 默认情况下 padavanonly 源码会自动处理，此处保持原样以延续成功案例

echo "物理诊断：diy-part1.sh 执行完毕，插件源已就绪，物理冲突已清理。"
