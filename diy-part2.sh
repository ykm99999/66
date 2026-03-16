#!/bin/bash

# 1. 物理粉碎缓存
rm -rf tmp

# 2. 物理溯源：定位并修复隐藏在补丁中的语法毒瘤
# 2410 分支的报错源于函数声明缺少闭合或 static inline 定义歧义
echo "正在对内核补丁进行像素级手术..."
find target/linux/generic/ -type f -name "*.patch" | xargs grep -l "nvmem_cell_read_variable_le_u64" | while read -r patch_file; do
    echo "发现目标补丁: $patch_file"
    # 强制修正 static inline 定义，并在声明处补全潜在的语法缺失
    sed -i 's/static inline int nvmem_cell_read_variable_le_u64/int __maybe_unused nvmem_cell_read_variable_le_u64/g' "$patch_file"
done

# 3. 物理纠偏：强制架构锁定为 mt7981
sed -i 's/CONFIG_TARGET_mediatek_filogic/CONFIG_TARGET_mediatek_mt7981/g' .config

# 4. 物理注入 SL3000 救砖核心插件与分区锁定
cat >> .config <<EOF
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_mt7981=y
CONFIG_TARGET_mediatek_mt7981_DEVICE_sl_3000-emmc=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_kmod-mmc=y
CONFIG_PACKAGE_kmod-mmc-mtk=y
CONFIG_PACKAGE_kmod-fs-f2fs=y
CONFIG_TARGET_KERNEL_PARTSIZE=10
CONFIG_TARGET_ROOTFS_PARTSIZE=20
EOF

echo "物理定论：补丁手术与配置注入已完成。"
