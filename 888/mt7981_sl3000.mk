# SL3000 eMMC 完整版设备定义（含科学上网、Docker）
define Device/mt7981_sl3000_emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := eMMC
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := sl,sl3000
  KERNEL_LOADADDR := 0x48000000
  DEVICE_PACKAGES := \
    luci luci-base luci-mod-system luci-theme-bootstrap \
    block-mount e2fsprogs f2fs-tools \
    kmod-fs-ext4 kmod-fs-f2fs \
    kmod-mtd kmod-mtd-rw \
    kmod-mmc-mtk \
    dropbear \
    lsblk blkid mount-utils \
    mtd-utils uboot-envtools \
    kmod-mt7981-eth kmod-mt7531 \
    luci-app-passwall2 xray-core chinadns-ng \
    shadowsocks-libev-ss-local shadowsocks-libev-ss-redir shadowsocks-libev-ss-tunnel \
    shadowsocks-rust-sslocal simple-obfs \
    docker-ce docker-compose kmod-br-netfilter kmod-ikconfig kmod-ipt-physdev \
    kmod-nf-ipt6 kmod-nf-ipvs kmod-veth kmod-fs-overlay luci-app-dockerman
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef

TARGET_DEVICES += mt7981_sl3000_emmc

# SL3000 SPI-NOR 救砖设备定义（精简，不含科学上网、Docker）
define Device/sl_3000-spi-nor
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 SPI-NOR (32MB)
  DEVICE_DTS := mt7981b-sl3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-spi-nor
  DEVICE_PACKAGES := \
    block-mount \
    uboot-envtools
  IMAGES := sysupgrade.bin
  IMAGE_SIZE := 25600k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef

TARGET_DEVICES += sl_3000-spi-nor
