#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware" "$STAGING_DIR_IMAGE"

# ========== 准备源码 ==========
cd "$WORKSPACE"
rm -rf immortalwrt-build
cp -r "$SOURCE_DIR/immortalwrt" immortalwrt-build
cd immortalwrt-build

# ========== Feeds 配置 & 清理 ==========
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

./scripts/feeds update -a
PROBLEM_PKGS="aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl python-rpds-py python-service-identity python-twisted python-docker python-jsonschema python-jsonschema-specifications python-referencing onionshare-cli onionshare weston wpewebkit libextractor python-bcrypt python-cryptography python-maturin podman ruby-yaml"
for pkg in $PROBLEM_PKGS; do find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true; done
rm -rf feeds/video feeds/telephony package/feeds
./scripts/feeds update -i
./scripts/feeds install -a
make package/symlinks

# ========== 物理注入 DTS ==========
# 路径兼容：同时注入旧版和新版内核路径
DTS_CONTENT=$(cat << 'EOF'
/dts-v1/;
#include "mt7981.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>
/ {
	model = "SL-3000 (1GB DDR4 Rescue Edition)";
	compatible = "sl,3000-emmc", "mediatek,mt7981";
	aliases { serial0 = &uart0; led-boot = &status_green_led; led-failsafe = &status_red_led; led-running = &status_green_led; led-upgrade = &status_blue_led; label-mac-device = &gmac0; };
	chosen { stdout-path = "serial0:115200n8"; bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000 root=/dev/mtdblock2 rootwait rw rootfstype=squashfs,f2fs"; };
	memory@40000000 { device_type = "memory"; reg = <0 0x40000000 0 0x40000000>; };
	leds { compatible = "gpio-leds"; 
		status_red: status-red { label = "red:status"; gpios = <&pio 10 GPIO_ACTIVE_LOW>; };
		status_green: status-green { label = "green:status"; gpios = <&pio 11 GPIO_ACTIVE_LOW>; linux,default-trigger = "heartbeat"; };
		status_blue: status-blue { label = "blue:status"; gpios = <&pio 12 GPIO_ACTIVE_LOW>; };
	};
	keys { compatible = "gpio-keys"; reset { label = "reset"; linux,code = <KEY_RESTART>; gpios = <&pio 1 GPIO_ACTIVE_LOW>; debounce-interval = <60>; }; };
};
&spi0 { pinctrl-names = "default"; pinctrl-0 = <&spi0_flash_pins>; status = "okay";
	flash@0 { compatible = "jedec,spi-nor"; reg = <0>; spi-max-frequency = <52000000>;
		partitions { compatible = "fixed-partitions"; #address-cells = <1>; #size-cells = <1>;
			partition@0 { label = "bl2"; reg = <0x0 0x380000>; read-only; };
			partition@380000 { label = "u-boot"; reg = <0x380000 0x80000>; read-only; };
			partition@400000 { label = "firmware"; reg = <0x400000 0x1C00000>; };
		};
	};
};
&mmc0 { status = "okay"; pinctrl-names = "default", "state_uhs"; pinctrl-0 = <&mmc0_pins_default>; pinctrl-1 = <&mmc0_pins_uhs>; bus-width = <8>; max-frequency = <52000000>; cap-mmc-highspeed; cap-mmc-hw-reset; non-removable; no-sd; no-sdio; };
&eth { status = "okay"; gmac0: mac@0 { compatible = "mediatek,eth-mac"; reg = <0>; phy-mode = "2500base-x"; fixed-link { speed = <2500>; full-duplex; pause; }; };
	mdio: mdio-bus { #address-cells = <1>; #size-cells = <0>;
		switch@0 { compatible = "mediatek,mt7531"; reg = <31>; reset-gpios = <&pio 39 GPIO_ACTIVE_LOW>; reset-delay-us = <10000>;
			ports { #address-cells = <1>; #size-cells = <0>;
				port@0 { reg = <0>; label = "lan1"; }; port@1 { reg = <1>; label = "lan2"; }; port@2 { reg = <2>; label = "lan3"; }; port@3 { reg = <3>; label = "wan"; };
				port@6 { reg = <6>; label = "cpu"; ethernet = <&gmac0>; phy-mode = "2500base-x"; fixed-link { speed = <2500>; full-duplex; pause; }; };
			};
		};
	};
};
&pio {
	spi0_flash_pins: spi0-pins { mux { function = "spi"; groups = "spi0", "spi0_wp_hold"; }; conf-pu { pins = "SPI0_CS", "SPI0_HOLD", "SPI0_WP"; bias-pull-up; }; };
	mmc0_pins_default: mmc0-pins-default { mux { function = "flash"; groups = "emmc_45"; }; conf-pu { pins = "EMMC_RSTB"; bias-pull-up; }; };
	mmc0_pins_uhs: mmc0-pins-uhs { mux { function = "flash"; groups = "emmc_45"; }; };
};
&uart0 { status = "okay"; }; &watchdog { status = "okay"; };
EOF
)
echo "$DTS_CONTENT" > target/linux/mediatek/dts/mt7981-sl-3000-emmc.dts
mkdir -p target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek
echo "$DTS_CONTENT" > target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mt7981-sl-3000-emmc.dts

# ========== 注入 Device 定义 ==========
sed -i '/define Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
cat >> "$FILOGIC_MK" <<EOF
define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := \$(DTS_DIR)
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := kmod-usb3 kmod-usb-storage kmod-usb-storage-uas f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils luci-app-passwall2 xray-core chinadns-ng docker-ce docker-compose luci-app-dockerman
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF

# ========== 配置生效 ==========
cp -v "$CONFIG_DIR/sl3000.config" .config
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
make defconfig
make -j1 V=s oldconfig
echo "$PWD" > "$WORKSPACE/build-dir.txt"
