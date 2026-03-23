#
# SL3000 设备定义 - 1GB 正常版
# 硬件：MT7981B + 1GB DDR4 + 128G eMMC + 32MB SPI NOR
#

# 可选：自定义 GPT 分区布局（若默认不合适，可取消注释并按需调整）
# GPT_LAYOUT := rootfs:2G,data:114G

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    luci-app-passwall2 \
    xray-core chinadns-ng \
    shadowsocks-libev-ss-local shadowsocks-libev-ss-redir shadowsocks-libev-ss-tunnel \
    shadowsocks-rust-sslocal simple-obfs \
    docker-ce docker-compose kmod-br-netfilter kmod-ikconfig kmod-ipt-physdev \
    kmod-nf-ipt6 kmod-nf-ipvs kmod-veth kmod-fs-overlay luci-app-dockerman
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  # 以下 GPT 镜像生成规则因当前版本不支持 gen_gpt 命令而被注释，如需生成可手动制作
  # IMAGES += gpt.bin
  # IMAGE/gpt.bin := gen_gpt | pad-rootfs | check-size
endef

TARGET_DEVICES += sl_3000-emmc
