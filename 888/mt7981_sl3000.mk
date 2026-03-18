define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (512MB rescue)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := \
    $(MT7981_USB_PKGS) \
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    ~gst1-plugins-base \
    ~gst1-plugins-good \
    ~gst1-plugins-ugly \
    ~libdmapsharing \
    ~luci-app-passwall \
    ~luci-app-rustdesk-server \
    ~luci-app-spotifyd \
    ~luci-app-clamav \
    ~luci-app-dufs \
    ~luci-app-openclash \
    ~luci-app-smartdns \
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
    ~procs \
    ~python-bcrypt \
    ~python-cryptography \
    ~python-maturin \
    ~python-setuptools-rust \
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
    ~python-referencing \
    ~ruby \
    ~ruby-yaml \
    ~podman \
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
    ~kamailio
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
