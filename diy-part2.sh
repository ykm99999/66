#!/bin/bash
# SL3000 V2 Physical Alignment Script
# 目标：修复 1GB 内存识别、解决串口乱码、锁定 256K 分区偏移

# 1. 物理时钟修复：解决 115200 乱码 (将 UART 时钟从 40M 提升至 200M)
# 修正 U-Boot 核心配置
sed -i 's/CONFIG_DEBUG_UART_CLOCK.*/CONFIG_DEBUG_UART_CLOCK=200000000/g' configs/mt7981_spim_nor_rfb_defconfig
sed -i 's/CONFIG_SYS_NS16550_CLK.*/CONFIG_SYS_NS16550_CLK=200000000/g' configs/mt7981_spim_nor_rfb_defconfig
# 修正 U-Boot 物理头文件
sed -i 's/#define CFG_SYS_NS16550_CLK.*/#define CFG_SYS_NS16550_CLK 200000000/g' include/configs/mt7981.h

# 2. 内存物理锁定：强制 1024MB (DDR4)
# 修改 ATF 内存初始化逻辑
sed -i 's/return 0x20000000/return 0x40000000/g' arm-trusted-firmware/plat/mediatek/mt7981/drivers/dram/emicfg.c
# 强制开启 DDR4 模式补丁
sed -i 's/mt7981_use_ddr4 = 0/mt7981_use_ddr4 = 1/g' arm-trusted-firmware/plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c

# 3. 引导偏移修复：锁定 256KB (0x40000) 寻址
# 修改 ATF 平台定义，确保 BL2 能找到 256K 处的 FIP
sed -i '/#define FLASH_FIP_BASE/d' arm-trusted-firmware/plat/mediatek/mt7981/include/platform_def.h
sed -i '/#define FLASH_FIP_MAX_SIZE/d' arm-trusted-firmware/plat/mediatek/mt7981/include/platform_def.h
cat >> arm-trusted-firmware/plat/mediatek/mt7981/include/platform_def.h <<EOF
#define FLASH_FIP_BASE (0x40000)
#define FLASH_FIP_MAX_SIZE (0x80000)
EOF

# 4. 物理跳转对齐：锁定 U-Boot 加载基址 0x41e00000
sed -i 's/CONFIG_TEXT_BASE.*/CONFIG_TEXT_BASE=0x41e00000/g' configs/mt7981_spim_nor_rfb_defconfig

# 5. 网络救砖通路：预设 IP 192.168.1.1
sed -i 's/CONFIG_IPADDR.*/CONFIG_IPADDR="192.168.1.1"/g' configs/mt7981_spim_nor_rfb_defconfig
sed -i 's/CONFIG_SERVERIP.*/CONFIG_SERVERIP="192.168.1.2"/g' configs/mt7981_spim_nor_rfb_defconfig

# 6. 设备树像素级对齐 (确保引用 1G 版 DTS)
sed -i 's/CONFIG_DEFAULT_DEVICE_TREE.*/CONFIG_DEFAULT_DEVICE_TREE="mt7981b-sl3000-emmc"/g' configs/mt7981_spim_nor_rfb_defconfig

# 7. 静默审计：禁用 EOF 冲突 (遵照用户指令)
# 脚本执行完毕
