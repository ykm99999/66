include ./common/common.mk

define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := 1GB-DDR4-32MB-SPI-Rescue
  DEVICE_DTS := mt7981b-sl3000-spi-nor
  SUPPORTED_DEVICES := siluo,sl3000-spi-nor

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  # 修正内核加载地址（二选一，建议 0x40800000）
  KERNEL_LOADADDR := 0x40800000
  # 或者 0x48000000

  # 生成标准救砖镜像
  IMAGES := rescue.bin
  IMAGE/rescue.bin := append-kernel | pad-to 6M | append-rootfs | pad-rootfs

  # 确保 initramfs 内核被正确包含
  ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
    IMAGE/rescue.bin := append-image-stage initramfs-kernel.bin | pad-to 6M
  endif

  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
