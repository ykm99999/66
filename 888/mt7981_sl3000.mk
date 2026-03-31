#
# SL3000 设备定义 - 1GB 救砖全家桶版
# 硬件：MT7981B + 1GB DDR4 + 32MB SPI NOR
#

define Device/sl_3000-spi-32m
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (1GB)
  
  # 🔴 物理对齐 1：必须与 diy-part1.sh 中复制的文件名像素级一致
  DEVICE_DTS := mt7981-sl-3000-emmc
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
    
  # 🔴 物理对齐 2：MT7981 必须使用 FIT 结构打包内核
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
    
  # 生成目标：网页升级包 + 32MB 物理编程器包
  IMAGES := sysupgrade.bin Spi-flash-32MB.bin
  
  # 标准网页升级包 (Tar 格式)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  
  # 🔴 物理对齐 3：合法宏调用与像素级偏移缝合
  # 使用 append-image 替代非法的 append-u-boot-elf
  # 0x000000 -> BL2
  # 0x080000 (512k) 或 0x100000 (1024k) -> FIP (此处采用 1M 对齐，兼容性最高)
  # 0x400000 (4096k) -> Firmware (内核+文件系统，采用 ITB 原始流)
  IMAGE/Spi-flash-32MB.bin := \
    append-image bl2-nor.bin | \
    pad-to 1024k | \
    append-image fip-nor.bin | \
    pad-to 4096k | \
    append-image squashfs-sysupgrade.itb | \
    pad-to 32768k
endef

TARGET_DEVICES += sl_3000-spi-32m
