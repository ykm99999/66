#
# SL3000 设备定义 - 1GB 救砖全家桶版
# 硬件：MT7981B + 1GB DDR4 + 128G eMMC + 32MB SPI NOR
#

define Device/sl_3000-spi-32m
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (1GB)
  DEVICE_DTS := mt7981-sl-3000
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi
  
  # 强制声明 1GB 内存识别
  DEVICE_DRAM_SIZE := 1024M
  
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    luci-app-passwall2 xray-core chinadns-ng \
    docker-ce docker-compose luci-app-dockerman
    
  # 生成救砖全家桶：升级包 + 32MB 物理包
  IMAGES := sysupgrade.bin Spi-flash-32MB.bin
  IMAGE_SIZE := 32768k
  
  # 物理缝合逻辑 (严格对齐 DTS 分区)
  # 1MB 预留给 BL2，3.5MB (3584k) 写入 FIP，4MB (4096k) 写入系统
  IMAGE/Spi-flash-32MB.bin := \
    append-u-boot-elf mt7981-bl2-nor | pad-to 3584k | \
    append-u-boot-elf mt7981-fip-nor | pad-to 4096k | \
    append-kernel | append-rootfs | pad-to 32768k | check-size
endef

TARGET_DEVICES += sl_3000-spi-32m
