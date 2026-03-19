#
# SL3000 (司络) 设备定义 - 1GB 正常版
# 硬件：MT7981B + 1GB DDR4 + 128G eMMC + 32MB SPI NOR
#

define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    ~gst1-plugins-base \
    ~gst1-plugins-good \
    ~gst1-plugins-ugly \
    ~gst1-plugins-bad \
    ~gst1-libav \
    ~dmapd \
    ~gmediarender \
    ~gnunet \
    ~gnunet-fuse \
    ~gnunet-fs \
    ~grilo-plugins \
    ~lcdgrilo \
    ~libdmapsharing \
    ~kamailio \
    ~smartdns \
    ~pymysql \
    ~python-orjson \
    ~python-paramiko \
    ~python-pyopenssl \
    ~python-rpds-py \
    ~python-service-identity \
    ~python-twisted \
    ~python-docker \
    ~python-jsonschema \
    ~python-jsonschema-specifications \
    ~python-referencing \
    ~luci-app-passwall \
    ~luci-app-rustdesk-server \
    ~luci-app-spotifyd \
    ~luci-app-clamav \
    ~luci-app-dufs \
    ~luci-app-openclash \
    ~luci-app-smartdns \
    ~libextractor \
    ~python-bcrypt \
    ~python-cryptography \
    ~python-maturin \
    ~python-setuptools-rust \
    ~podman \
    ~ruby \
    ~ruby-yaml \
    ~aardvark-dns \
    ~netavark \
    ~pdns-recursor \
    ~cargo-c \
    ~arp-whisper \
    ~yggdrasil-jumper \
    ~onionshare-cli \
    ~onionshare \
    ~weston \
    ~wpewebkit \
    ~shadowsocks-rust \
    ~shadowsocks-rust-sslocal \
    ~shadowsocks-rust-ssserver \
    ~shadow-tls \
    ~tuic-client \
    ~tuic-server \
    ~rustdesk-server \
    ~spotifyd \
    ~clamav \
    ~dufs \
    ~eza \
    ~fish \
    ~lsd \
    ~bottom \
    ~ripgrep \
    ~procs
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc

# -----------------------------------------------------------------------------
# 编程器救砖镜像（可选，用于 SPI NOR 编程器烧录）
# 布局（偏移量基于 U-Boot 配置）：
#   0x000000 - 0x1FFFFF : BL2 (填充至2M)
#   0x200000 - 0x3FFFFF : FIP (U-Boot)
#   0x400000 - 0xBFFFFF : 内核 (8M)
#   0xC00000 - 0x1FFFFFF : 根文件系统 (20M)
#
# 若要启用，请取消注释以下块，并确保已生成对应的 BL2/FIP 文件：
#   - mt7981-nor-ddr4-bl2-1g.img   (1GB 版 BL2)
#   - mt7981_sl3000_nor-fip.bin    (U-Boot FIP)
#
# define Device/sl_3000-emmc-programmer
#   $(Device/sl_3000-emmc)
#   IMAGES += nor-programmer-dump.bin
#   IMAGE/nor-programmer-dump.bin := \
#	append-image-stage mt7981-nor-ddr4-bl2-1g.img | pad-to 2048k | \
#	append-image-stage mt7981_sl3000_nor-fip.bin | pad-to 4096k | \
#	append-kernel | pad-to 12M | \
#	append-rootfs | pad-to 32M | check-size 32M
# endef
# TARGET_DEVICES += sl_3000-emmc-programmer
