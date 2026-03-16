#!/bin/bash

# --- V6 物理清理：切除故障源 ---
rm -rf package/5g-modem
rm -rf package/feeds/packages/rd05a1

# --- V6 物理注入 ATF Makefile ---
# 锁定路径并确保目录存在
mkdir -p package/boot/arm-trusted-firmware-mediatek
ATF_PATH="package/boot/arm-trusted-firmware-mediatek/Makefile"

printf 'include $(TOPDIR)/rules.mk\ninclude $(INCLUDE_DIR)/kernel.mk\n\n' > $ATF_PATH
printf 'PKG_NAME:=arm-trusted-firmware-mediatek\nPKG_VERSION:=2024.10\nPKG_RELEASE:=1\n\n' >> $ATF_PATH
printf 'PKG_SOURCE_PROTO:=git\nPKG_SOURCE_URL:=https://github.com/ykm888/66.git\n' >> $ATF_PATH
printf 'PKG_SOURCE_VERSION:=sl3000-clean-source\nPKG_MIRROR_HASH:=skip\n\n' >> $ATF_PATH
printf 'include $(INCLUDE_DIR)/package.mk\n\n' >> $ATF_PATH
printf 'define Package/arm-trusted-firmware-mediatek/Default\n  SECTION:=boot\n  CATEGORY:=Boot Loaders\n  TITLE:=ATF for MediaTek SL3000 (DDR4)\n  DEPENDS:=@TARGET_mediatek\nendef\n\n' >> $ATF_PATH
printf 'define Trusted-Firmware-A/mt7981-sl3000-emmc\n  NAME:=SL-3000 (eMMC, DDR4)\n  PLAT:=mt7981\n  BOOT_DEVICE:=emmc\n  DRAM_TYPE_NAME:=ddr4\nendef\n\nTFA_TARGETS:=mt7981-sl3000-emmc\n\n' >> $ATF_PATH

# 关键：使用 __TAB__ 占位符，彻底解决第 47 行报错
printf 'define Build/Compile\n' >> $ATF_PATH
printf '__TAB__$(foreach target,$(TFA_TARGETS), \\\n' >> $ATF_PATH
printf '__TAB____TAB__$(MAKE) -C $(PKG_BUILD_DIR) \\\n' >> $ATF_PATH
printf '__TAB____TAB__CROSS_COMPILE=$(TARGET_CROSS) \\\n' >> $ATF_PATH
printf '__TAB____TAB__PLAT=mt7981 \\\n' >> $ATF_PATH
printf '__TAB____TAB__BOOT_DEVICE=emmc \\\n' >> $ATF_PATH
printf '__TAB____TAB__DRAM_TYPE_NAME=ddr4 \\\n' >> $ATF_PATH
printf '__TAB____TAB__all \\\n' >> $ATF_PATH
printf '__TAB__)\n' >> $ATF_PATH
printf 'endef\n\n' >> $ATF_PATH

printf 'define Package/arm-trusted-firmware-mediatek/install/default\n' >> $ATF_PATH
printf '__TAB__$(INSTALL_DIR) $(STAGING_DIR_IMAGE)\n' >> $ATF_PATH
printf '__TAB__$(CP) $(PKG_BUILD_DIR)/build/mt7981/release/bl2.img $(STAGING_DIR_IMAGE)/$(1)-bl2.img\n' >> $ATF_PATH
printf 'endef\n\n' >> $ATF_PATH

printf '$(foreach target,$(TFA_TARGETS), \\\n  $(eval $(call Package/arm-trusted-firmware-mediatek/Default)) \\\n  $(eval $(call Package/arm-trusted-firmware-mediatek/install/default,$(target))) \\\n  $(eval $(call BuildPackage,arm-trusted-firmware-mediatek-$(target))) \\\n)\n' >> $ATF_PATH

# --- 物理修正：执行占位符替换 (核心修复动作) ---
sed -i 's/__TAB__/\t/g' $ATF_PATH

# --- V6 物理对齐 DTS ---
mkdir -p package/boot/uboot-mediatek/files/arch/arm/dts
printf '/dts-v1/;\n#include "mt7981.dtsi"\n/ {\n  model = "SL-3000 (ykm888 Hardened)";\n  compatible = "mediatek,mt7981-sl3000", "mediatek,mt7981";\n  memory@40000000 {\n    device_type = "memory";\n    reg = <0x40000000 0x20000000>;\n  };\n  chosen { stdout-path = &uart0; };\n};\n&uart0 { status = "okay"; };\n&mmc0 { status = "okay"; bus-width = <8>; cap-mmc-highspeed; non-removable; };\n&spi0 { status = "okay"; };\n' > package/boot/uboot-mediatek/files/arch/arm/dts/mt7981-sl3000.dts

echo "V6 物理加固脚本执行完毕：Makefile 语法死穴已消除。"
