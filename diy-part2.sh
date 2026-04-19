#!/bin/bash
# [物理审计] 锁定 V18 稳态：仅针对 3806 行做物理隔断修复

set -euo pipefail

FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
REPO_888="../888"

echo "=== 1. 物理基因纠偏：修复 Makefile 粘连 ==="
if [ -f "$FILOGIC_MK" ]; then
    # [原文照抄] 精准清理旧定义，确保构建幂等
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    
    # [原子级修复] 在文件末尾强制添加两个绝对换行，彻底消除物理粘连导致的语法报错
    echo -e "\n\n" >> "$FILOGIC_MK"
    
    # [原文照抄] 必须物理引用仓库中的原文进行追加，严禁脚本内硬编码
    cat "$REPO_888/mt7981_sl3000.mk" >> "$FILOGIC_MK"
    
    # [原文照抄] 像素级校准：确保缩进为标准 Tab (\t)
    sed -i 's/^    /\t/g' "$FILOGIC_MK"
    echo "✅ filogic.mk 物理对齐完成"
fi

echo "=== 2. 物理链路闭合：DTS 双向注入 ==="
DTS_NAME="mt7981b-sl3000-emmc.dts"
if [ -f "$REPO_888/$DTS_NAME" ]; then
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
    mkdir -p "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7981b-sl-3000-emmc.dts"
fi

echo "=== 3. 物理覆盖：Config 母本 ==="
if [ -f "$REPO_888/sl3000.config" ]; then
    cp -f "$REPO_888/sl3000.config" .config
fi
