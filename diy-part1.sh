#!/bin/bash

# --- 旗舰工厂：功能补全与 32MB 锁定 ---

echo "### 物理执行：插件补全与分区表对齐 ###"

# 1. 物理注入 LuCI 及基础功能插件
{
  echo "CONFIG_PACKAGE_luci=y"
  echo "CONFIG_PACKAGE_luci-theme-bootstrap=y"
  echo "CONFIG_PACKAGE_luci-app-ksmbd=y"
  echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y"
  echo "CONFIG_PACKAGE_kmod-fs-f2fs=y"
  echo "CONFIG_PACKAGE_kmod-mmc=y"
} >> .config

# 2. 物理锁定 32MB 分区表极限 (6MB Kernel / 20MB Rootfs)
sed -i 's/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=6/' .config
sed -i 's/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=20/' .config

echo "物理定论：零件补齐与 32MB 像素级对齐完成。"
