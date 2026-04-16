#!/bin/bash
set -euo pipefail

# 物理修复：锁定终端环境
export TERM=xterm-256color

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"
IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 物理修复 ATF 源码 (彻底解决未定义与重定义) ==========
echo "=== Executing ATF Absolute Physical Fix V9 ==="
cd $SOURCE_DIR/arm-trusted-firmware

# 物理修补点 1：给系统公共头文件加锁，防止欢迎词冲突
sed -i 's/#define FIRMWARE_WELCOME_STR.*/#ifndef FIRMWARE_WELCOME_STR\n\0\n#endif/' include/plat/common/common_def.h

# 物理修补点 2：物理注入补全后的 platform_def.h (包含 TRNG 定义)
cat > plat/mediatek/mt7981/include/platform_def.h << 'EOF'
/*
 * Copyright (c) 2021, MediaTek Inc. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 * SL3000 Rescue Firmware - Version 2 (Fixed TRNG & RAM Aligned)
 */
#ifndef PLATFORM_DEF_H
#define PLATFORM_DEF_H

#include <common/interrupt_props.h>
#include <drivers/arm/gic_common.h>
#include <lib/utils_def.h>
#include "mt7981_def.h"

#define PLATFORM_LINKER_FORMAT		"elf64-littleaarch64"
#define PLATFORM_LINKER_ARCH		aarch64

#if defined(IMAGE_BL1)
#define PLATFORM_STACK_SIZE		0x440
#elif defined(IMAGE_BL2)
#define PLATFORM_STACK_SIZE		0x1000
#elif defined(IMAGE_BL31)
#define PLATFORM_STACK_SIZE		0x800
#elif defined(IMAGE_BL32)
#define PLATFORM_STACK_SIZE		0x440
#endif

/* 物理锁定：SL3000 自定义欢迎词 */
#ifndef FIRMWARE_WELCOME_STR
#define FIRMWARE_WELCOME_STR		"Booting Trusted Firmware (SL3000 1GB)\n"
#endif

#define PLATFORM_MAX_AFFLVL		MPIDR_AFFLVL2
#define PLAT_MAX_PWR_LVL		U(2)
#define PLAT_MAX_RET_STATE		U(1)
#define PLAT_MAX_OFF_STATE		U(2)
#define PLATFORM_SYSTEM_COUNT		1
#define PLATFORM_CLUSTER_COUNT		1
#define PLATFORM_CLUSTER0_CORE_COUNT	2
#define PLATFORM_CORE_COUNT		2
#define PLATFORM_MAX_CPUS_PER_CLUSTER	2
#define PLATFORM_NUM_AFFS		(PLATFORM_SYSTEM_COUNT + PLATFORM_CLUSTER_COUNT + PLATFORM_CORE_COUNT)

/* 硬件寄存器定义补全：物理解决 TRNG undeclared 错误 */
#define TRNG_BASE			(0x1020F000)
#define TRNG_SIZE			(0x1000)

/* 物理对齐：SL3000 1GB RAM 布局 */
#define IMAGE_LOAD_ADDR			(0x40000000)
#define TZRAM_BASE			(0x43000000)
#define TZRAM_SIZE			(0x20000)
#define TZRAM2_BASE			(TZRAM_BASE + TZRAM_SIZE)
#define TZRAM2_SIZE			(0x10000)
#define SOC_CHIP_ID			U(0x7981)

#define BL2_LIMIT			(0x280000)
#define BL31_BASE			(TZRAM_BASE + 0x1000)
#define BL31_LIMIT			(TZRAM_BASE + TZRAM_SIZE)
#define BL32_BASE			(TZRAM2_BASE)
#define BL32_LIMIT			(TZRAM2_BASE + TZRAM2_SIZE)
#define BL33_BASE			(0x41e00000)

/* 物理对齐：Flash 布局 */
#define FLASH_FIP_BASE			(0x40000)
#define FLASH_FIP_MAX_SIZE		(0x80000)

#define MAX_IO_DEVICES			U(3)
#define MAX_IO_HANDLES			U(4)
#define MAX_IO_BLOCK_DEVICES		1
#define FIP_DECOMP_TEMP_BASE		(0x42000000)
#define FIP_DECOMP_TEMP_SIZE		(0x400000)

#define PLAT_PHY_ADDR_SPACE_SIZE	(1ULL << 32)
#define PLAT_VIRT_ADDR_SPACE_SIZE	(1ULL << 32)
#define MAX_XLAT_TABLES			4
#define MAX_MMAP_REGIONS		16
#define CACHE_WRITEBACK_SHIFT		6
#define CACHE_WRITEBACK_GRANULE		(1 << CACHE_WRITEBACK_SHIFT)

#define PLAT_ARM_G1S_IRQ_PROPS(grp) \
	INTR_PROP_DESC(MT_IRQ_SEC_SGI_0, GIC_HIGHEST_SEC_PRIORITY, grp, GIC_INTR_CFG_EDGE)
#define PLAT_ARM_G0_IRQ_PROPS(grp)

#endif /* PLATFORM_DEF_H */
EOF

# ========== 2. 强制锁定 DDR4 补丁 (原文照抄) ==========
mkdir -p plat/mediatek/mt7981/drivers/dram
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>
extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
void mtk_mem_init(void) {
	mt7981_use_ddr4 = 1;
	NOTICE("EMI: Using DDR4 settings forced\n");
	mtk_mem_init_real();
}
EOF

# ========== 3. 编译各组件 (原文照抄) ==========
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-emmc.bin

cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

cd "$IMMORTALWRT_BUILD_DIR"
make -j$(nproc) V=s
mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f \( -name "*sysupgrade*" -o -name "*.img.gz" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
