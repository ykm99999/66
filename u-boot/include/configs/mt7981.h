/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Configuration for MediaTek MT7981 SoC
 * SL3000 Rescue Firmware - Version 2 (Clock & RAM Aligned)
 */

#ifndef __MT7981_H
#define __MT7981_H

/* * 物理修复：波特率校准
 * 现象：115200 乱码，576000 正常。
 * 原因：底层串口时钟源为 200MHz。
 * 修复：硬编码为 200,000,000，使 U-Boot 计算出正确的分频以回归 115200。
 */
#define CFG_SYS_NS16550_CLK		200000000
#define CFG_BAUDRATE			115200

/* * 救砖专属环境变量
 * 预设物理分区表：256k(bl2), 512k(fip)
 * 预设 TFTP 救砖 IP 逻辑
 */
#define CFG_EXTRA_ENV_SETTINGS	\
	"ethaddr=00:0c:43:26:60:01\0" \
	"ipaddr=192.168.1.1\0" \
	"serverip=192.168.1.2\0" \
	"loadaddr=0x46000000\0" \
	"console=ttyS0,115200\0" \
	"mtdparts=nor0:256k(bl2),512k(fip),64k(u-boot-env),-(firmware)\0" \
	"update_fip=tftp ${loadaddr} fip-nor.bin && sf probe 0 && sf erase 0x40000 0x80000 && sf write ${loadaddr} 0x40000 ${filesize}\0" \
	"update_uboot=tftp ${loadaddr} u-boot.bin && sf probe 0 && sf erase 0x40000 0x80000 && sf write ${loadaddr} 0x40000 ${filesize}\0" \
	"bootcmd=sf probe 0 && sf read ${loadaddr} 0x40000 0x80000 && bootm ${loadaddr}\0"

#endif
