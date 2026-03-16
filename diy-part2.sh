#!/bin/bash

# 1. 物理粉碎临时文件
rm -rf tmp

# 2. 物理语法热修复 (解决 mediatek-ge.c 编译报错)
echo "正在物理执行：全域化解 NVMEM 语法冲突..."
grep -rl "static inline int nvmem_cell_read_variable_le_u64" target/linux/generic/ | xargs sed -i 's/static inline int nvmem_cell_read_variable_le_u64/int __maybe_unused nvmem_cell_read_variable_le_u64/g' 2>/dev/null || true

# 3. 物理残留清理 (彻底抹除 701-712 段冲突)
echo "正在物理执行：清理博通/DSA 冲突补丁..."
find target/linux/generic/backport-5.4/ -name "70[1-9]-*.patch" -delete
find target/linux/generic/backport-5.4/ -name "71[0-2]-*.patch" -delete

# 4. 物理对齐 SL3000 eMMC 分区布局
# 针对 eMMC 版，内核与文件系统空间可以适当放大，但为了稳定，我们保持 10M/20M 经典对齐
sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=10/' .config
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

# 5. 修改默认 IP 为 192.168.31.1
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

echo "### 物理定论：SL3000 救砖种子逻辑已注入 ###"
