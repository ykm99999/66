#
# Copyright (c) 2023, MediaTek Inc. All rights reserved.
# Copyright (c) 2026, ykm888 (Physical Hardening for SL-3000)
#
# SPDX-License-Identifier: BSD-3-Clause
#

include lib/libfdt/libfdt.mk
include lib/xz/xz.mk

# BL2 image options
BL2_IS_AARCH64		:=	1
BL2_SIG_TYPE		:=	sha256+rsa-pss
BL2_IMG_HDR_SOC		:=	mt7986

# --- 【物理加固注入点】 ---
# 强制注入 1MB 偏移宏 (0x100000)，确保驱动程序读取正确位置
BL2_CPPFLAGS		+=	-DMTK_UBOOT_OFFSET_IN_SPI=0x100000
# 注入设备树路径定义
BL2_CPPFLAGS		+=	-DDTB_PATH=\"$(BUILD_PLAT)/fdts/$(DTS_NAME).dtb\"

FDT_SOURCES		+=	fdts/$(DTS_NAME).dts

BL2_CPPFLAGS		+=	-I$(APSOC_COMMON)/drivers/spi			\
				-I$(MTK_PLAT_SOC)/drivers/gpio			\
				-I$(MTK_PLAT_SOC)/drivers/spi			\
				-I$(MTK_PLAT_SOC)/drivers/dram

# --- BL2 核心源码列表 ---
BL2_SOURCES		:=	common/desc_image_load.c			\
				common/image_decompress.c			\
				drivers/delay_timer/delay_timer.c		\
				drivers/delay_timer/generic_delay_timer.c	\
				drivers/gpio/gpio.c				\
				drivers/io/io_storage.c				\
				drivers/io/io_block.c				\
				drivers/io/io_fip.c				\
				lib/cpus/aarch64/cortex_a53.S			\
				$(XZ_SOURCES)					\
				$(APSOC_COMMON)/drivers/uart/aarch64/hsuart.S	\
				$(APSOC_COMMON)/drivers/spi/mtk_spi.c		\
				$(APSOC_COMMON)/drivers/wdt/mtk_wdt.c		\
				$(MTK_PLAT_SOC)/aarch64/plat_helpers.S		\
				$(MTK_PLAT_SOC)/aarch64/platform_common.c	\
				$(MTK_PLAT_SOC)/bl2/dtb.S			\
				$(MTK_PLAT_SOC)/bl2/bl2_plat_init.c		\
				$(MTK_PLAT_SOC)/drivers/timer/timer.c		\
				$(MTK_PLAT_SOC)/drivers/spi/boot_spi.c		\
				$(MTK_PLAT_SOC)/drivers/gpio/mt7981_gpio.c	\
				$(MTK_PLAT_SOC)/drivers/pll/pll.c

# 强制包含你的加固驱动
ifeq ($(BOOT_DEVICE),nor)
BL2_SOURCES		+=	$(MTK_PLAT_SOC)/bl2/bl2_dev_spi_nor.c
endif

# Include dram driver files
include $(MTK_PLAT_SOC)/drivers/dram/dram.mk

# Dual-FIP & Security
include $(APSOC_COMMON)/bl2/dual_fip.mk
include $(APSOC_COMMON)/bl2/tbbr.mk
include $(APSOC_COMMON)/bl2/ar.mk

ifeq ($(BL2_COMPRESS),1)
BL2_CPPFLAGS		+=	-DUSING_BL2PL
endif

ifeq ($(ENABLE_JTAG), 1)
BL2_CPPFLAGS		+=	-DENABLE_JTAG
endif

# BL2 内存布局起始点
BL2_BASE		:=	0x201000
