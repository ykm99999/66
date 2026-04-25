# SPDX-License-Identifier: GPL-2.0-or-later
define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Rescue (1GB DDR4 / 32MB NOR)
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-emmc
  DEVICE_DRAM_SIZE := 1024M
  SOC := mt7981
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := uboot-envtools block-mount kmod-mmc kmod-mmc-mtk \
                     kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs
endef
TARGET_DEVICES += mt7981_sl3000_spi_rescue
