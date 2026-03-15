#!/bin/bash

# --- 物理路径溯源 ---
# 如果 GITHUB_WORKSPACE 为空（本地测试用），则取当前目录的上一级
PATCH_DIR="${GITHUB_WORKSPACE:-$(pwd)/..}/888"
OPENWRT_ROOT=$(pwd)

echo "物理诊断：源码根目录 -> $OPENWRT_ROOT"
echo "物理诊断：补丁集路径 -> $PATCH_DIR"

# 1. 物理劫持 U-Boot 索引
UBOOT_MAKEFILE="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_MAKEFILE" ]; then
    sed -i '/mt7981_xiaomi_mi-router-wr30u/a \\tmt7981_sl3000_nor \\' "$UBOOT_MAKEFILE"
    echo "物理成功：已注入 U-Boot 索引。"
else
    echo "物理致命错误：找不到 $UBOOT_MAKEFILE" && exit 1
fi

# 2. 补丁强制覆盖（带物理存在校验）
declare -A PATCH_MAP=(
    ["atf-Makefile"]="package/boot/arm-trusted-firmware-mediatek/Makefile"
    ["uboot-Makefile"]="package/boot/uboot-mediatek/Makefile"
    ["mt7981.mk"]="target/linux/mediatek/image/mt7981.mk"
    ["mt7981_sl3000_nor_defconfig"]="package/boot/uboot-mediatek/files/mt7981_sl3000_nor_defconfig"
)

mkdir -p package/boot/uboot-mediatek/files

for src in "${!PATCH_MAP[@]}"; do
    target="${PATCH_MAP[$src]}"
    if [ -f "$PATCH_DIR/$src" ]; then
        cp -f "$PATCH_DIR/$src" "$target"
        echo "物理对齐：$src -> $target"
    else
        echo "物理致命错误：补丁 $src 在 $PATCH_DIR 中不存在！" && exit 1
    fi
done

# 3. 网口逻辑物理修正
NETWORK_FILE="target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if [ -f "$NETWORK_FILE" ]; then
    sed -i '/sl,3000-emmc/d' "$NETWORK_FILE"
    sed -i '/casat,ar3000m/a \\tsl,3000-emmc)\n\t\tucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"\n\t\t;;' "$NETWORK_FILE"
    echo "物理成功：网口逻辑已修正。"
fi

echo "物理定论：所有补丁已完成原子级注入。"
