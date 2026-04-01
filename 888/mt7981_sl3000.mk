define Device/sl_3000-spi-nor
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (32MB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi-nor
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage \
    block-mount \
    uboot-envtools \
    ttyd
  IMAGES := sysupgrade.bin
  IMAGE_SIZE := 32768k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef

TARGET_DEVICES += sl_3000-spi-nor
