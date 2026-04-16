/*
 * Copyright (c) 2022, MediaTek Inc. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 * * SL3000 Physical Alignment: Forced 1024MB DRAM Configuration
 * This file dictates the memory map for both BL2 loading and U-Boot passing.
 */

#include <stdint.h>
#include <mt7981_soc_def.h>

/**
 * @brief 物理寻址核心函数
 * * 返回 MT7981 平台的物理 DRAM 容量。
 * 只有在此处准确返回 1GB，BL2 才会允许将 FIP/U-Boot 加载到高位内存地址，
 * 同时防止系统因为内存地址溢出而导致的硬件挂起。
 * * @return unsigned int 物理内存大小（字节）
 */
unsigned int mtk_get_dram_size_config(void)
{
    /* * 物理锁定：1024MB = 0x40000000 字节
     * 对应 SL3000 的 1GB DDR4 硬件规格
     */
    return 0x40000000; 
}

/**
 * @brief 内存控制器物理初始化配置
 * * 此函数在 dram_init 流程中被调用。
 * 对于救砖包，我们依赖核心初始化脚本，此处保持标准入口以满足链接一致性。
 */
void emi_init_setting(void)
{
    /* * 物理逻辑：此处通常配合 mtk_mem_init.c 中的逻辑使用。
     * 保持为空或标准宏调用，确保不发生非法地址访问。
     */
}
