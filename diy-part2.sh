#!/bin/bash

# --- V9 物理清理 ---
rm -rf package/5g-modem
rm -rf package/feeds/packages/rd05a1

# --- V9 物理校准：解决 "recipe commences before first target" ---
# 无论底层仓库如何，这里强行将所有行首空格转为硬 Tab
# 物理逻辑：匹配行首的空格并替换为 \t
if [ -f "package/boot/arm-trusted-firmware-mediatek/Makefile" ]; then
    sed -i 's/^[[:space:]]\+/\t/g' package/boot/arm-trusted-firmware-mediatek/Makefile
    # 针对 define 块内的特殊二重校准
    sed -i 's/^\t\t/\t/g' package/boot/arm-trusted-firmware-mediatek/Makefile
    echo "Makefile 物理校准完成。"
else
    echo "物理警告：底层仓库未检测到 Makefile！"
fi

# --- V9 物理注入 DTS (由于不含 Tab，可用 printf 安全注入) ---
mkdir -p package/boot/uboot-mediatek/files/arch/arm/dts
printf '/dts-v1/;\n#include "mt7981.dtsi"\n/ {\n  model = "SL-3000 (ykm888 Hardened)";\n  compatible = "mediatek,mt7981-sl3000", "mediatek,mt7981";\n  memory@40000000 {\n    device_type = "memory";\n    reg = <0x40000000 0x20000000>;\n  };\n  chosen { stdout-path = &uart0; };\n};\n&uart0 { status = "okay"; };\n&mmc0 { status = "okay"; bus-width = <8>; cap-mmc-highspeed; non-removable; };\n&spi0 { status = "okay"; };\n' > package/boot/uboot-mediatek/files/arch/arm/dts/mt7981-sl3000.dts

echo "V9 脚本物理准备就绪。"
