#!/bin/bash

# 1. 【延续 V2 逻辑】物理净空：彻底切除导致循环依赖的 5G 故障包
rm -rf package/5g-modem
rm -rf package/feeds/packages/rd05a1

# 2. 【延续 V3 逻辑】物理注入：锁定 ATF (DDR4 训练核心)
cat << 'EOF' > package/boot/arm-trusted-firmware-mediatek/Makefile
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=arm-trusted-firmware-mediatek
PKG_VERSION:=2024.10
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ykm888/66.git
PKG_SOURCE_VERSION:=sl3000-clean-source
PKG_MIRROR_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/arm-trusted-firmware-mediatek/Default
  SECTION:=boot
  CATEGORY:=Boot Loaders
  TITLE:=ATF for MediaTek SL3000 (DDR4)
  DEPENDS:=@TARGET_mediatek
endef

define Trusted-Firmware-A/mt7981-sl3000-emmc
  NAME:=SL-3000 (eMMC, DDR4)
  PLAT:=mt7981
  BOOT_DEVICE:=emmc
  DRAM_TYPE_NAME:=ddr4
endef

TFA_TARGETS:=mt7981-sl3000-emmc

define Build/Compile
	$(foreach target,$(TFA_TARGETS), \
		$(MAKE) -C $(PKG_BUILD_DIR) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		PLAT=mt7981 \
		BOOT_DEVICE=emmc \
		DRAM_TYPE_NAME=ddr4 \
		all \
	)
endef

define Package/arm-trusted-firmware-mediatek/install/default
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)
	$(CP) $(PKG_BUILD_DIR)/build/mt7981/release/bl2.img $(STAGING_DIR_IMAGE)/$(1)-bl2.img
endef

$(foreach target,$(TFA_TARGETS), \
  $(eval $(call Package/arm-trusted-firmware-mediatek/Default)) \
  $(eval $(call Package/arm-trusted-firmware-mediatek/install/default,$(target))) \
  $(eval $(call BuildPackage,arm-trusted-firmware-mediatek-$(target))) \
)
EOF

# 3. 【延续 V3 逻辑】物理注入：锁定 U-Boot (eMMC 引导核心)
cat << 'EOF' > package/boot/uboot-mediatek/Makefile
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_VERSION:=2024.10
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ykm888/66.git
PKG_SOURCE_VERSION:=sl3000-clean-source
PKG_MIRROR_HASH:=skip

PKG_BUILD_DEPENDS:=arm-trusted-firmware-tools/host

include $(INCLUDE_DIR)/u-boot.mk
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/host-build.mk

define U-Boot/Default
  BUILD_TARGET:=mediatek
  BUILD_SUBTARGET:=filogic
  UBOOT_IMAGE:=u-boot.fip
  HIDDEN:=1
endef

define U-Boot/mt7981_sl3000_emmc
  NAME:=SL-3000 (Private u-boot, eMMC, DDR4)
  BUILD_DEVICES:=sl_3000-emmc
  UBOOT_CONFIG:=mt7981_sl-3000-emmc
  BL2_SOC:=mt7981
  BL2_BOOTDEV:=emmc
  BL2_DDRTYPE:=ddr4
  DEPENDS:=+arm-trusted-firmware-mediatek-mt7981-sl3000-emmc
endef

UBOOT_TARGETS:=mt7981_sl3000_emmc

$(eval $(call BuildPackage/U-Boot))
EOF

# 4. 【关键 V4 物理增强】强制将所有 Makefile 命令行的空格修复为物理 Tab 键
# 这将彻底解决 "recipe commences before first target" 报错
sed -i 's/^	//g' package/boot/arm-trusted-firmware-mediatek/Makefile
sed -i 's/^	//g' package/boot/uboot-mediatek/Makefile
sed -i 's/^    /\t/g' package/boot/arm-trusted-firmware-mediatek/Makefile
sed -i 's/^    /\t/g' package/boot/uboot-mediatek/Makefile
sed -i 's/^	/\t/g' package/boot/arm-trusted-firmware-mediatek/Makefile
sed -i 's/^	/\t/g' package/boot/uboot-mediatek/Makefile

echo "SL3000 延续版 V4 物理修复脚本执行完毕。"
