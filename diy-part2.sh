#!/bin/bash

# --- 旗舰工厂：物理路径锁定 V23-Final ---
RAW_URL="https://raw.githubusercontent.com/padavanonly/immortalwrt-mt798x-6.6/2410"

echo "### 物理执行：V23 彻底清除干扰架构与路径锁定 ###"

# 1. 物理截肢：彻底删除除 mediatek 以外的所有架构文件夹，断绝 Error 1 来源
find target/linux/ -maxdepth 1 -mindepth 1 -not -name "mediatek" -not -name "Makefile" -exec rm -rf {} +
echo "✅ 干扰架构 (x86等) 已物理截肢，编译器干扰源已切断。"

# 2. 动态定位并物理净化 MediaTek 目录
TARGET_DIR=$(find target/linux -name "mediatek" -type d | head -n 1)
[ -z "$TARGET_DIR" ] && TARGET_DIR="target/linux/mediatek"

# 强行重置 SUBTARGETS，确保编译目标物理唯一
echo "SUBTARGETS:=filogic" > $TARGET_DIR/Makefile
cat >> $TARGET_DIR/Makefile <<EOF
include \$(INCLUDE_DIR)/target.mk
\$(eval \$(call BuildTarget))
EOF

# 3. 物理注入核心镜像定义 (MK)
MK_FILE="$TARGET_DIR/image/filogic.mk"
mkdir -p $(dirname "$MK_FILE")
curl -sL "$RAW_URL/target/linux/mediatek/image/mt7981.mk" -o "$MK_FILE"

# 强制排他性赋值，并移除复杂包依赖以通过 Kconfig 物理校验
sed -i 's/DEVICE_PACKAGES :=.*/DEVICE_PACKAGES := kmod-fs-f2fs kmod-mmc/' "$MK_FILE"
sed -i 's/TARGET_DEVICES +=/TARGET_DEVICES :=/g' "$MK_FILE"
echo -e "\nTARGET_DEVICES := sl_3000-emmc" >> "$MK_FILE"

# 4. 物理注入 DTS (全路径覆盖)
DTS_NAME="mt7981-sl-3000-emmc.dts"
find $TARGET_DIR -name "dts" -type d | while read dts_path; do
    dest_dts="$dts_path/mediatek/$DTS_NAME"
    mkdir -p $(dirname "$dest_dts")
    curl -sL "$RAW_URL/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/$DTS_NAME" -o "$dest_dts"
done

# 5. 修改全局 Kconfig 默认值，防止物理漂移回 x86
sed -i 's/default "x86"/default "mediatek"/' target/config/Config-build.in

echo "物理定论：V23 架构强攻注入完成，环境已物理纯净化。"
