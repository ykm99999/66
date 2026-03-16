#!/bin/bash

# 物理强刷：清理旧缓存防止架构冲突
rm -rf tmp

# 物理纠偏：确保目标指向 mt7981 而非 filogic
sed -i 's/CONFIG_TARGET_mediatek_filogic/CONFIG_TARGET_mediatek_mt7981/g' .config

# 物理补丁：由于是 eMMC 救砖版，强制开启 MMC 相关支持
echo "CONFIG_PACKAGE_kmod-mmc=y" >> .config
echo "CONFIG_PACKAGE_kmod-mmc-mtk=y" >> .config
