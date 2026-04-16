/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Configuration for MediaTek MT7981 SoC
 * SL3000 Rescue Firmware - Version 2 (Clock Aligned)
 * Physical Fix: Correcting 576000 baudrate offset back to 115200
 */

#ifndef __MT7981_H
#define __MT7981_H

/* * 物理时钟校准：
 * 针对 SL3000 硬件，串口时钟源实际运行在 200MHz (PERI_BUS)。
 * 此处必须定义为 200,000,000，否则 115200 会变成 576000。
 */
#define CFG_SYS_NS16550_CLK		200000000
#define CFG_BAUDRATE			115200

/* 救砖专属环境变量：预设物理分区与自动化刷机宏 */
#define CFG_EXTRA_ENV_SETTINGS	\
	"ethaddr=00:0c:43:26:60:01\0" \
	"ipaddr=192.168.1.1\0" \
	"serverip=192.168.1.2\0" \
	"loadaddr=0x46000000\0" \
	"console=ttyS0,115200\0" \
	"bootconf=config-1\0" \
	"bootfile=sysupgrade.bin\0" \
	"mtdparts=nor0:256k(bl2),512k(fip),64k(u-boot-env),-(firmware)\0" \
	"update_fip=tftp ${loadaddr} fip-nor.bin && sf probe 0 && sf erase 0x40000 0x80000 && sf write ${loadaddr} 0x40000 ${filesize}\0" \
	"update_uboot=tftp ${loadaddr} u-boot.bin && sf probe 0 && sf erase 0x40000 0x80000 && sf write ${loadaddr} 0x40000 ${filesize}\0" \
	"bootcmd=sf probe 0 && sf read ${loadaddr} 0x40000 0x80000 && bootm ${loadaddr}\0"

#endif
