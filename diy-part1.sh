#!/bin/bash
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# [物理审计] 针对 SL3000-eMMC 1024M 版本的像素级修复脚本
# 适用环境：ImmortalWrt / OpenWrt 24.10 (Kernel 6.6)

# --- 步骤 1: 物理格式纠偏 (解决 missing separator 报错) ---
# 溯源：强制将 filogic.mk 中非标准的 4 空格缩进物理转换为标准 Tab
# 并清理行尾可能存在的不可见空白字符，防止解析崩溃
if [ -f "target/linux/mediatek/image/filogic.mk" ]; then
    echo "🛠️ 物理审计：纠偏 filogic.mk 格式..."
    sed -i 's/^    /\t/g' target/linux/mediatek/image/filogic.mk
    sed -i 's/^  /\t/g' target/linux/mediatek/image/filogic.mk
    sed -i 's/[[:space:]]*$//' target/linux/mediatek/image/filogic.mk
fi

# --- 步骤 2: 物理旁路注入 (彻底解决 mkimage 编译死锁) ---
# 溯源：从 tools 编译索引中彻底抹除 mkimage，强制使用宿主机预装工具
# 解决 Error: The configuration requires explicit update.
if [ -f "tools/Makefile" ]; then
    echo "🛠️ 物理审计：物理切断 tools/mkimage 索引..."
    sed -i 's/tools-$(CONFIG_HOST_UBOOT_MKIMAGE) += mkimage//g' tools/Makefile
    sed -i 's/tools-y += mkimage//g' tools/Makefile
fi

# --- 步骤 3: 物理链路补全 (DTS 像素级注入) ---
# 溯源：将设备树同时注入到 Target 路径和 Kernel 6.6 搜索路径
# 解决 KERNEL_LOADADDR 相关的编译查找失败
DTS_NAME="mt7981b-sl3000-emmc.dts"
# 注意：此时处于 openwrt 根目录，假设 DTS 已通过 workflow 预放在特定位置
# 如果 DTS 在 main-repo/888/ 下，请确保流程中已执行 cp 操作
TARGET_DTS_PATH="target/linux/mediatek/dts/$DTS_NAME"
KERNEL_DTS_PATH="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/$DTS_NAME"

mkdir -p "$(dirname "$TARGET_DTS_PATH")"
mkdir -p "$(dirname "$KERNEL_DTS_PATH")"

# 如果当前目录存在 DTS，则执行物理同步
if [ -f "$DTS_NAME" ]; then
    cp -f "$DTS_NAME" "$TARGET_DTS_PATH"
    cp -f "$DTS_NAME" "$KERNEL_DTS_PATH"
    echo "✅ 物理审计：DTS 链路双向对齐完成"
fi

# --- 步骤 4: Feeds 注入 (保持原文基因) ---
# 示例：添加外部插件仓库
# echo 'src-git small8 https://github.com/kenzok8/small-package' >> feeds.conf.default

echo "✅ diy-part1.sh 物理审计执行完毕，全链路风险点已封锁。"
