#!/bin/bash

# 1. 物理环境初始化
rm -rf tmp

# 2. 物理自愈：修复 NVMEM 接口定义冲突 (核心保险)
# 作用：解决 drivers/net/phy/mediatek-ge.c 等文件编译报错
echo "正在物理执行：修复 NVMEM 语法冲突..."
find target/linux/generic/ -type f -name "*.patch" | xargs grep -l "nvmem_cell_read_variable_le_u64" | xargs sed -i 's/static inline int nvmem_cell_read_variable_le_u64/int __maybe_unused nvmem_cell_read_variable_le_u64/g' 2>/dev/null || true

# 3. 物理残留爆破
# 即使手动删除了补丁，这里作为双重防线，确保博通相关冲突补丁彻底不在场
rm -f target/linux/generic/backport-5.4/70[1-9]-*.patch
rm -f target/linux/generic/backport-5.4/71[0-2]-*.patch

# 4. 物理分区锁定：适配 SL3000 (32MB Flash)
# 作用：防止生成的固件太大导致刷机失败。设定内核10MB，根分区20MB。
echo "正在物理执行：锁定 32MB 闪存分区布局..."
sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=10/' .config
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

# 5. 修改默认 IP 为 192.168.31.1 (物理纠偏)
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

echo "### 物理定论：脚本执行完毕，环境已就绪 ###"
