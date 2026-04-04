define Device/sl_3000-spi-nor
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (32MB Flash)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi-nor
  # 救砖全家桶（含你之前要的 spi、mmc、分区、uboot工具）
  DEVICE_PACKAGES := \
    block-mount \
    uboot-envtools \
    ttyd \
    mmc-utils \
    spi-utils \
    mtd-utils \
    kmod-mtd-rw

  # 关键：只生成完整编程器固件 .bin，不生成 sysupgrade
  IMAGES := factory.bin
  IMAGE_SIZE := 32768k

  # 完整一体固件（直接用于编程器烧录 SPI NOR 32MB）
  IMAGE/factory.bin := append-kernel | append-rootfs | pad-rootfs | pad-to 32768k
endef

TARGET_DEVICES += sl_3000-spi-nor
