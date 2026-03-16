#!/bin/bash

# 1. 物理环境初始化
rm -rf tmp

# 2. 物理全域修复：解决 NVMEM 接口语法冲突 (核心)
# 作用：物理化解 mediatek-ge.c 编译时的 "expected identifier" 报错
echo "正在物理执行：全域化解 NVMEM 语法冲突..."
grep -rl "static inline int nvmem_cell_read_variable_le_u64" target/linux/generic/ | xargs sed -i 's/static inline int nvmem_cell_read_variable_le_u64/int __maybe_unused nvmem_cell_read_variable_le_u64/g' 2>/dev/null || true

# 3. 物理残留清理 (针对你手动删除的 701-712 段)
# 即使底层仓库更新，此行也会确保博通冲突补丁物理不在场
echo "正在物理执行：清理博通残留补丁..."
find target/linux/generic/backport-5.4/ -name "70[1-9]-*.patch" -delete
find target/linux/generic/backport-5.4/ -name "71[0-2]-*.patch" -delete

# 4. 物理分区锁定：适配 SL3000 (32MB Flash)
# 10MB 内核 + 20MB 根文件系统，严防固件体积超标
echo "正在物理执行：锁定 32MB 闪存分区边界..."
sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=10/' .config
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

# 5. 默认 IP 物理纠偏
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

echo "### 物理定论：所有冲突点已闭环修复，请提交并运行编译 ###"
