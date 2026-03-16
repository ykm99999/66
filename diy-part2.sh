#!/bin/bash
# 职责：物理纠偏、分区锁定、插件注入

echo "### 物理执行：SL3000 分区锁定与插件补全 ###"

# 1. 物理架构纠偏（防止 2410 分支残留 filogic 代号）
sed -i 's/CONFIG_TARGET_mediatek_filogic/CONFIG_TARGET_mediatek_mt7981/g' .config

# 2. 物理注入 LuCI 及 eMMC 核心零件 (直接追加到工作流搬运过来的 .config)
cat >> .config <<EOF
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-app-ksmbd=y
CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y
CONFIG_PACKAGE_kmod-fs-f2fs=y
CONFIG_PACKAGE_kmod-mmc=y
CONFIG_PACKAGE_kmod-mmc-mtk=y
EOF

# 3. 物理锁定 32MB 分区表极限 (修正为你要求的 6MB/20MB)
# 注意：如果内核编译后超过 6MB 会报错，到时需物理调大 KERNEL_PARTSIZE
sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=6/' .config
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

echo "物理定论：SL3000 像素级对齐执行完毕。"
