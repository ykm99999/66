#!/bin/bash
# [物理审计] 针对 SL3000-eMMC 的像素级基因注入脚本
# 策略：只负责“物理对齐”，不负责“耗时编译”

set -euo pipefail

# 1. 物理环境对齐
# 在 GitHub Actions 中，diy-part2.sh 执行时已经在 openwrt 根目录
IMMORTAL_DIR=$(pwd)
REPO_888="../888" # 假设 888 仓库在 openwrt 同级目录

echo "=== 1. 物理基因注入：纠偏 filogic.mk ==="
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

if [ -f "$REPO_888/mt7981_sl3000.mk" ]; then
    # 物理清除旧定义 (防止重复注入导致的变量冲突)
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    
    # 物理修补：确保文件末尾有且只有一个换行符，防止 cat 产生“粘连”导致的 separator 错误
    sed -i '$a\\' "$FILOGIC_MK"
    
    # 注入新定义
    cat "$REPO_888/mt7981_sl3000.mk" >> "$FILOGIC_MK"
    
    # 像素级缩进对齐：将 4 空格物理重置为 Tab
    sed -i 's/^    /\t/g' "$FILOGIC_MK"
    echo "✅ Device MK 注入并执行像素级格式纠偏"
fi

echo "=== 2. 物理链路闭合：DTS 与 Config ==="
# [1] 注入 DTS (双向注入，确保内核 6.6 索引成功)
DTS_NAME="mt7981b-sl3000-emmc.dts"
if [ -f "$REPO_888/$DTS_NAME" ]; then
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
    mkdir -p "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
    cp -f "$REPO_888/$DTS_NAME" "target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7981b-sl-3000-emmc.dts"
    echo "✅ DTS 物理链路已双向闭合"
fi

# [2] 注入配置母本
if [ -f "$REPO_888/sl3000.config" ]; then
    cp -f "$REPO_888/sl3000.config" .config
    # 物理封印：严禁任何交互询问
    echo "CONFIG_BUILDBOT=y" >> .config
    echo "CONFIG_ALL_KMODS=n" >> .config
    echo "✅ .config 物理基因注入完成"
fi

echo "=== 3. 物理致盲：切断 mconf 交互通路 ==="
# 溯源修复：防止因为 .config 不对齐触发 menuconfig 弹窗
mkdir -p scripts/config
echo -e '#!/bin/sh\nexit 1' > scripts/config/mconf-cfg.sh
chmod +x scripts/config/mconf-cfg.sh

echo "=== 4. 物理旁路：预制工具链占位 (针对 mkimage 报错) ==="
# 配合 Workflow 中的 u-boot-tools，物理标记 mkimage 已安装
mkdir -p staging_dir/host/stamp
touch staging_dir/host/stamp/.mkimage_installed
# 物理切断 Makefile 内部编译索引
if [ -f "tools/Makefile" ]; then
    sed -i 's/tools-$(CONFIG_HOST_UBOOT_MKIMAGE) += mkimage//g' tools/Makefile
    sed -i 's/tools-y += mkimage//g' tools/Makefile
fi

echo "✅ diy-part2.sh 物理审计执行完毕。后续编译交由 Workflow 承接。"
