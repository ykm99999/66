#!/bin/bash
# [物理审计] 严格执行物理执行三准则：原文照抄，严禁脑补修改

set -euo pipefail

FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
REPO_888="../888"

# 1. 物理格式纠偏：修复 missing separator 报错
if [ -f "$FILOGIC_MK" ]; then
    # [原文照抄] 精准切除已存在的定义，防止重复叠加
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    
    # [最小修补] 仅在文件末尾物理追加一个换行，确保后续 cat 注入不发生物理粘连
    sed -i '$a\\' "$FILOGIC_MK"
    
    # [原文照抄] 恢复使用你仓库中的原始文件进行物理注入
    cat "$REPO_888/mt7981_sl3000.mk" >> "$FILOGIC_MK"
    
    # [原文照抄] 像素级校准，确保所有缩进物理对齐为 Tab
    sed -i 's/^    /\t/g' "$FILOGIC_MK"
fi

# 2. DTS 链路闭合：物理复刻之前的双注入逻辑
DTS_NAME="mt7981b-sl3000-emmc.dts"
if [ -f "$REPO_888/$DTS_NAME" ]; then
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
    mkdir -p "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7981b-sl-3000-emmc.dts"
fi

# 3. .config 物理覆盖
if [ -f "$REPO_888/sl3000.config" ]; then
    cp -f "$REPO_888/sl3000.config" .config
fi
