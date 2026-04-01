# ========== 注入设备定义 ==========
# 原有 eMMC 定义（保留）
echo "" >> $FILOGIC_MK
echo "# SL3000 eMMC 设备定义（由 diy-part1.sh 注入）" >> $FILOGIC_MK
echo "define Device/sl_3000-emmc" >> $FILOGIC_MK
# ... 原有 eMMC 定义内容 ...
echo "TARGET_DEVICES += sl_3000-emmc" >> $FILOGIC_MK

# 新增 SPI-NOR 救砖设备定义
echo "" >> $FILOGIC_MK
echo "# SL3000 SPI-NOR 救砖设备定义（由 diy-part1.sh 注入）" >> $FILOGIC_MK
echo "define Device/sl_3000-spi-nor" >> $FILOGIC_MK
echo "  DEVICE_VENDOR := SL" >> $FILOGIC_MK
echo "  DEVICE_MODEL := 3000 SPI-NOR (32MB)" >> $FILOGIC_MK
echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> $FILOGIC_MK
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> $FILOGIC_MK
echo "  SUPPORTED_DEVICES := sl,3000-spi-nor" >> $FILOGIC_MK
echo "  DEVICE_PACKAGES := \\" >> $FILOGIC_MK
echo "    kmod-usb3 kmod-usb-storage \\" >> $FILOGIC_MK
echo "    block-mount \\" >> $FILOGIC_MK
echo "    uboot-envtools \\" >> $FILOGIC_MK
echo "    ttyd" >> $FILOGIC_MK
echo "  IMAGES := sysupgrade.bin" >> $FILOGIC_MK
echo "  IMAGE_SIZE := 32768k" >> $FILOGIC_MK
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> $FILOGIC_MK
echo "endef" >> $FILOGIC_MK
echo "TARGET_DEVICES += sl_3000-spi-nor" >> $FILOGIC_MK

# ========== 配置 .config ==========
cp -v $CONFIG_DIR/sl3000.config .config || exit 1

# 设置平台
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config

# 启用 eMMC 设备（保留原有配置）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

# 启用 SPI-NOR 救砖设备
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 确保没有冲突的禁用设置
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc/d' .config   # 先删除再添加（确保唯一）
sed -i '/CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor/d' .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# 生成基础配置
make defconfig || exit 1
