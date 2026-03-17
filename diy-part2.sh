#!/bin/bash

# 1. 物理清理冲突
rm -rf package/5g-modem
rm -rf package/feeds/packages/rd05a1

# 2. 物理校准 ATF Makefile (确保小写 include 和硬 Tab)
ATF_PATH="package/boot/arm-trusted-firmware-mediatek/Makefile"
if [ -f "$ATF_PATH" ]; then
    sed -i 's/Include/include/g' "$ATF_PATH"
    sed -i 's/^[[:space:]]\+/\t/g' "$ATF_PATH"
fi

# 3. 物理注入 U-Boot 定义 (与 .config 中的 CONFIG_PACKAGE_uboot-mediatek-mt7981_sl3000_emmc 对齐)
UBOOT_PATH="package/boot/uboot-mediatek/Makefile"
if [ -f "$UBOOT_PATH" ]; then
    # 检查是否已有定义，没有则物理插入
    if ! grep -q "mt7981_sl3000_emmc" "$UBOOT_PATH"; then
        sed -i '/define U-Boot\/mt7981-sd-emmc/i \
define U-Boot/mt7981_sl3000_emmc\n  NAME:=SL-3000 (eMMC)\n  BUILD_SUBTARGET:=filogic\n  BUILD_DEVICES:=mediatek_mt7981\n  DEPENDS:=+arm-trusted-firmware-mediatek-mt7981-sl3000-emmc\nendef\n' "$UBOOT_PATH"
        
        # 物理加入目标编译列表
        sed -i 's/UBOOT_TARGETS := \\/UBOOT_TARGETS := mt7981_sl3000_emmc \\/' "$UBOOT_PATH"
    fi
fi

echo "SL3000 救砖零件物理对齐完成。"
