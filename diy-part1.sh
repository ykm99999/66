#!/bin/bash
# [物理审计] 锁定本地配置，仅执行像素级格式纠偏

# 1. 物理对齐 MK 文件 (解决 missing separator 报错)
# 溯源诊断：强制将 filogic.mk 中所有 4 个空格的“假缩进”物理转换为 1 个标准 Tab
# 这一步是修复 11s 处 Error 2 的核心红线
sed -i 's/^    /\t/g' target/linux/mediatek/image/filogic.mk
sed -i 's/^  /\t/g' target/linux/mediatek/image/filogic.mk

# 2. 物理链路闭合：DTS 路径强制索引
# 确保 DTS 存在于内核编译脚本的搜索路径 files-6.6 下
# 即使不拉取仓库，也要确保它在源码目录树中处于活跃状态
KERNEL_DTS_DIR="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
LOCAL_DTS="target/linux/mediatek/dts/mt7981b-sl3000-emmc.dts"

if [ -f "$LOCAL_DTS" ]; then
    mkdir -p "$KERNEL_DTS_DIR"
    cp -f "$LOCAL_DTS" "$KERNEL_DTS_DIR/mt7981b-sl3000-emmc.dts"
    echo "✅ 物理审计：DTS 链路已闭合到 6.6 内核路径"
else
    echo "⚠️ 警告：未在 target 路径找到本地 DTS，请确认文件是否存在"
fi

echo "✅ 物理审计：格式纠偏完成，阻止 missing separator 报错再次触发。"
