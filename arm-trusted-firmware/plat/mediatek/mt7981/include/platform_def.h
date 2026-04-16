/*
 * Copyright (c) 2021, MediaTek Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * SL3000 Rescue Firmware - Version 2 (Flash & RAM Aligned)
 */

#ifndef PLATFORM_DEF_H
#define PLATFORM_DEF_H

#include <common/interrupt_props.h>
#include <drivers/arm/gic_common.h>
#include <lib/utils_def.h>

#include "mt7981_def.h"

/*******************************************************************************
 * Platform binary types for linking
 ******************************************************************************/
#define PLATFORM_LINKER_FORMAT		"elf64-littleaarch64"
#define PLATFORM_LINKER_ARCH		aarch64

/*******************************************************************************
 * Generic platform constants
 ******************************************************************************/

#if defined(IMAGE_BL1)
#define PLATFORM_STACK_SIZE		0x440
#elif defined(IMAGE_BL2)
#define PLATFORM_STACK_SIZE		0x1000
#elif defined(IMAGE_BL31)
#define PLATFORM_STACK_SIZE		0x800
#elif defined(IMAGE_BL32)
#define PLATFORM_STACK_SIZE		0x440
#endif

#define FIRMWARE_WELCOME_STR		"Booting Trusted Firmware (SL3000 1GB)\n"

#define PLATFORM_MAX_AFFLVL		MPIDR_AFFLVL2
#define PLAT_MAX_PWR_LVL		U(2)
#define PLAT_MAX_RET_STATE		U(1)
#define PLAT_MAX_OFF_STATE		U(2)
#define PLATFORM_SYSTEM_COUNT		1
#define PLATFORM_CLUSTER_COUNT		1
#define PLATFORM_CLUSTER0_CORE_COUNT	2
#define PLATFORM_CORE_COUNT		2
#define PLATFORM_MAX_CPUS_PER_CLUSTER	2
#define PLATFORM_NUM_AFFS		(PLATFORM_SYSTEM_COUNT + \
					 PLATFORM_CLUSTER_COUNT + \
					 PLATFORM_CORE_COUNT)

/*******************************************************************************
 * Platform memory map related constants (1GB RAM Support)
 ******************************************************************************/
#define IMAGE_LOAD_ADDR			(0x40000000)
#define TZRAM_BASE			(0x43000000)
#define TZRAM_SIZE			(0x20000)
#define TZRAM2_BASE			(TZRAM_BASE + TZRAM_SIZE)
#define TZRAM2_SIZE			(0x10000)
#define SOC_CHIP_ID			U(0x7981)

/*******************************************************************************
 * BL2 & BL33 (U-Boot) Defines
 ******************************************************************************/
#define BL2_LIMIT			(0x280000)
#define BL31_BASE			(TZRAM_BASE + 0x1000)
#define BL31_LIMIT			(TZRAM_BASE + TZRAM_SIZE)
#define BL32_BASE			(TZRAM2_BASE)
#define BL32_LIMIT			(TZRAM2_BASE + TZRAM2_SIZE)

/* 物理锁定：U-Boot 在内存中的起始地址，必须与 defconfig 的 CONFIG_TEXT_BASE 一致 */
#define BL33_BASE			(0x41e00000)

/*******************************************************************************
 * Flash Layout Architecture (Critical Fix)
 * 物理对齐：BL2 寻找 FIP 的偏移位置
 ******************************************************************************/
/* * 物理对齐逻辑：
 * 0x00000 - 0x3FFFF : BL2 (256KB)
 * 0x40000 - 0xBFFFF : FIP / U-Boot (512KB)
 */
#define FLASH_FIP_BASE			(0x40000)
#define FLASH_FIP_MAX_SIZE		(0x80000)

/*******************************************************************************
 * IO Device Constants
 ******************************************************************************/
#define MAX_IO_DEVICES			U(3)
#define MAX_IO_HANDLES			U(4)
#define MAX_IO_BLOCK_DEVICES		1

/*******************************************************************************
 * Decompression & MMU
 ******************************************************************************/
#define FIP_DECOMP_TEMP_BASE		(0x42000000)
#define FIP_DECOMP_TEMP_SIZE		(0x400000)

#define PLAT_PHY_ADDR_SPACE_SIZE	(1ULL << 32)
#define PLAT_VIRT_ADDR_SPACE_SIZE	(1ULL << 32)
#define MAX_XLAT_TABLES			4
#define MAX_MMAP_REGIONS		16

#define CACHE_WRITEBACK_SHIFT		6
#define CACHE_WRITEBACK_GRANULE		(1 << CACHE_WRITEBACK_SHIFT)

/* GIC Interrupt Props Placeholder */
#define PLAT_ARM_G1S_IRQ_PROPS(grp) \
	INTR_PROP_DESC(MT_IRQ_SEC_SGI_0, GIC_HIGHEST_SEC_PRIORITY, grp, GIC_INTR_CFG_EDGE)
#define PLAT_ARM_G0_IRQ_PROPS(grp)

#endif /* PLATFORM_DEF_H */
