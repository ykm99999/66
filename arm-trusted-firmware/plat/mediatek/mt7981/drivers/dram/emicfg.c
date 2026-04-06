/*
 * Copyright (c) 2021, MediaTek Inc. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Minimal implementation for SL3000 rescue firmware (1GB DDR4)
 */

#include <stdint.h>

/*
 * 物理对齐函数：强制返回 1024MB 偏移量
 * 用于告知 U-Boot 和内核正确的 DRAM 大小
 */
unsigned int mtk_get_dram_size_config(void)
{
    return 0x40000000;  /* 1GB = 0x40000000 */
}

/*
 * 内存时序控制逻辑（最小化实现）
 * 救砖固件不需要复杂配置，空实现即可
 */
void emi_init_setting(void)
{
    /* 空实现，避免未定义的 mmio 操作 */
}

/*
 * 必须提供 mtk_mem_init 函数，因为 bl2_plat_init.c 中的 initcall 数组会调用它
 */
void mtk_mem_init(void)
{
    /* 空实现，满足链接要求 */
}
