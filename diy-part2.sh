#!/bin/bash
# [物理审计] 严格执行物理执行三准则：原文照抄，锁定稳态

set -euo pipefail

FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
REPO_888="../888"

echo "=== 1. 物理格式纠偏：修复 3806 行 missing separator ==="
if [ -f "$FILOGIC_MK" ]; then
    # [原文照抄] 精准清理，确保幂等性
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    
    # [最小修补] 物理断行：在原文件末尾强制打入一个空行，彻底解决粘连报错
    echo "" >> "$FILOGIC_MK"
    
    # [原文照抄] 必须使用你仓库中的原始文件追加，严禁使用 EOF 注入
    cat "$REPO_888/mt7981_sl3000.mk" >> "$FILOGIC_MK"
    
    # [原文照抄] 像素级校准：确保所有缩进物理对齐为 Tab
    sed -i 's/^    /\t/g' "$FILOGIC_MK"
fi

echo "=== 2. 物理链路闭合：DTS 双注入 ==="
DTS_NAME="mt7981b-sl3000-emmc.dts"
if [ -f "$REPO_888/$DTS_NAME" ]; then
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
    mkdir -p "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7981b-sl-3000-emmc.dts"
fi

echo "=== 3. Config 物理覆盖 ==="
if [ -f "$REPO_888/sl3000.config" ]; then
    cp -f "$REPO_888/sl3000.config" .config
fi
