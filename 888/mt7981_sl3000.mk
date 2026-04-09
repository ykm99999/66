include ./common/common.mk

define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := 1GB-DDR4-32MB-SPI-Rescue
  DEVICE_DTS := mt7981b-sl3000-emmc                     # 修正1：与实际 DTS 文件名匹配
  SUPPORTED_DEVICES := siluo,sl3000-spi-nor

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  KERNEL_LOADADDR := 0x40800000

  # 修正2：使用标准 append-initramfs 命令
  IMAGES := rescue.bin
  IMAGE/rescue.bin := append-initramfs

  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear \
    kmod-leds-gpio kmod-button-hotplug                 # 可选，建议添加
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
