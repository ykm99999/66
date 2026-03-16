#!/bin/bash

# --- 旗舰工厂：功能补全与分区锁定 ---

echo "### 物理执行：零件补全与 32MB 救砖锁定 ###"

# 1. 物理注入 LuCI 及功能插件
{
  echo "CONFIG_PACKAGE_luci=y"
  echo "CONFIG_PACKAGE_luci-theme-bootstrap=y"
  echo "CONFIG_PACKAGE_luci-app-ksmbd=y"
  echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y"
  echo "CONFIG_PACKAGE_kmod-fs-f2fs=y"
  echo "CONFIG_PACKAGE_kmod-mmc=y"
  echo "CONFIG_PACKAGE_f2fsck=y"
  echo "CONFIG_PACKAGE_ksmbd-utils=y"
} >> .config

# 2. 物理锁定分区表 (6MB 内核 + 20MB Rootfs，确保总包 < 32MB)
sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=6/' .config
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

echo "物理定论：插件补全与分区表对齐完成。"
