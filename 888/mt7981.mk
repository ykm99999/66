#
# SL3000 (司络) 设备定义
# 硬件：MT7981B + 1GB DDR4 + 128G eMMC + 32MB SPI NOR
# 包含两个变体：1GB 正常版 和 512MB 救砖版
#

# 1GB 正常版（用于日常使用）
define Device/sl_3000-emmc-1g
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981-sl-3000-emmc-1g
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
	luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc-1g

# 512MB 救砖版（用于内存降容救砖）
define Device/sl_3000-emmc-512m
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (512MB rescue)
  DEVICE_DTS := mt7981-sl-3000-emmc-512m
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
	luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc-512m

# -----------------------------------------------------------------------------
# 编程器救砖镜像（可选）
# 用于通过 SPI 编程器直接烧录 32MB NOR 闪存。
# 依赖预编译的 BL2 和 FIP 镜像，需放置在 $(STAGING_DIR_IMAGE)/ 下。
# 布局（偏移量基于 U-Boot 配置）：
#   0x000000 - 0x1FFFFF : BL2 (填充至2M边界)
#   0x200000 - 0x3FFFFF : FIP (U-Boot)
#   0x400000 - 0xBFFFFF : 内核 (8M)
#   0xC00000 - 0x1FFFFFF : 根文件系统 (20M)
#
# 若要启用，请取消注释以下块，并确保已生成对应的 BL2/FIP 文件：
#   - mt7981-nor-ddr4-bl2-1g.img   (1GB 版 BL2)
#   - mt7981-nor-ddr4-bl2-512m.img (512MB 版 BL2)
#   - mt7981_sl3000_nor-fip.bin    (U-Boot FIP，与内存大小无关)
#
# define Device/sl_3000-emmc-1g-programmer
#   $(Device/sl_3000-emmc-1g)
#   IMAGES += nor-programmer-dump.bin
#   IMAGE/nor-programmer-dump.bin := \
#	append-image-stage mt7981-nor-ddr4-bl2-1g.img | pad-to 2048k | \
#	append-image-stage mt7981_sl3000_nor-fip.bin | pad-to 4096k | \
#	append-kernel | pad-to 12M | \
#	append-rootfs | pad-to 32M | check-size 32M
# endef
# TARGET_DEVICES += sl_3000-emmc-1g-programmer
#
# define Device/sl_3000-emmc-512m-programmer
#   $(Device/sl_3000-emmc-512m)
#   IMAGES += nor-programmer-dump.bin
#   IMAGE/nor-programmer-dump.bin := \
#	append-image-stage mt7981-nor-ddr4-bl2-512m.img | pad-to 2048k | \
#	append-image-stage mt7981_sl3000_nor-fip.bin | pad-to 4096k | \
#	append-kernel | pad-to 12M | \
#	append-rootfs | pad-to 32M | check-size 32M
# endef
# TARGET_DEVICES += sl_3000-emmc-512m-programmer
