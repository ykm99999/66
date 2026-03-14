/*
 * Copyright (c) 2023, MediaTek Inc. All rights reserved.
 * Copyright (c) 2026, ykm888 (SL-3000 Physical Hardening)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef PLATFORM_DEF_H
#define PLATFORM_DEF_H

#define PLAT_PRIMARY_CPU		0x0

/* * --- 【物理命门：FIP 偏移硬化】 ---
 * 必须锁定为 1MB (0x100000)，与驱动和 DTS 严格对齐。
 * 这是 BL2 跳转到 U-Boot 的唯一物理基准。
 */
#define MTK_FIP_BASE			0x100000
#define MTK_FIP_MAX_SIZE		0x200000

/* * --- 【内存布局：物理安全区】 ---
 */
#define TZRAM_BASE			0x40000000
#define TZRAM_SIZE			0x30000

#define DRAM_BASE			0x40000000
#define DRAM_SIZE			0x10000000

/* * --- 【硬件拓扑：物理参数】 ---
 */
#define PLATFORM_CACHE_LINE_SIZE	64
#define PLATFORM_CLUSTER_COUNT		1
#define PLATFORM_CORE_COUNT_PER_CLUSTER	2
#define PLATFORM_CORE_COUNT		PLATFORM_CORE_COUNT_PER_CLUSTER
#define PLAT_MAX_PWR_LVL		2
#define PLAT_MAX_RET_STATE		1
#define PLAT_MAX_OFF_STATE		2

/* * --- 【外设基地址：链路闭环】 ---
 */
#define UART0_BASE			0x11002000
#define MTK_WDT_BASE			0x10007000

#endif /* PLATFORM_DEF_H */
