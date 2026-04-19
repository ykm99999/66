#!/bin/bash
# [物理审计] 像素级还原 V18 稳态：原文照抄，严禁乱改

set -euo pipefail

FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
REPO_888="../888"

echo "=== 1. 物理基因纠偏：修复 Makefile 粘连报错 ==="
if [ -f "$FILOGIC_MK" ]; then
    # [原文照抄] 精准切除旧定义
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    
    # [最小修补] 物理隔离：在原文件末尾强制打入一个换行符，确保 cat 注入时不发生物理粘连
    echo "" >> "$FILOGIC_MK"
    
    # [原文照抄] 恢复使用 888 仓库中的原始 mk 文件进行物理注入
    cat "$REPO_888/mt7981_sl3000.mk" >> "$FILOGIC_MK"
    
    # [原文照抄] 像素级校准：确保所有缩进对齐为 Tab
    sed -i 's/^    /\t/g' "$FILOGIC_MK"
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
