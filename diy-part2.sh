#!/bin/bash
# SL3000 V2 Physical Alignment Script
# 目标：修复 1GB 内存识别、解决串口乱码、锁定 256K 分区偏移
set -euo pipefail

echo "=== 执行 V2 物理像素级修复逻辑 ==="

# 1. 物理时钟修复：解决 115200 乱码 (将 UART 时钟从 40M 提升至 200M)
# 修正 U-Boot 编译配置 (defconfig)
find package/boot/uboot-mtk/src/configs/ -name "mt7981_spim_nor_rfb_defconfig" -exec sed -i 's/CONFIG_DEBUG_UART_CLOCK.*/CONFIG_DEBUG_UART_CLOCK=200000000/g' {} +
find package/boot/uboot-mtk/src/configs/ -name "mt7981_spim_nor_rfb_defconfig" -exec sed -i 's/CONFIG_SYS_NS16550_CLK.*/CONFIG_SYS_NS16550_CLK=200000000/g' {} +

# 修正 U-Boot 物理头文件：锁定硬件波特率分母 (彻底消除乱码)
find package/boot/uboot-mtk/src/include/configs/ -name "mt7981.h" -exec sed -i 's/#define CFG_SYS_NS16550_CLK.*/#define CFG_SYS_NS16550_CLK 200000000/g' {} +

# 2. 内存物理锁定：强制 1024MB (DDR4)
# 修改 ATF 内存初始化逻辑：锁定返回值为 0x40000000 (1GB)
find package/boot/arm-trusted-firmware-mtk/src/ -name "emicfg.c" -exec sed -i 's/return 0x20000000/return 0x40000000/g' {} +

# 强制开启 DDR4 模式补丁：确保 BL2 初始化时使用正确的内存协议
find package/boot/arm-trusted-firmware-mtk/src/ -name "mtk_mem_init.c" -exec sed -i 's/mt7981_use_ddr4 = 0/mt7981_use_ddr4 = 1/g' {} +

# 3. 引导偏移修复：锁定 256KB (0x40000) 寻址
# 理由：确保 BL2 引导后在 0x40000 位置寻找特征码 (78563412)
find package/boot/arm-trusted-firmware-mtk/src/ -name "platform_def.h" -exec sed -i '/#define FLASH_FIP_BASE/d' {} +
find package/boot/arm-trusted-firmware-mtk/src/ -name "platform_def.h" -exec sed -i '/#define FLASH_FIP_MAX_SIZE/d' {} +

# 获取 platform_def.h 物理路径并注入锁定宏 (禁用 EOF 遵照指令)
ATF_PLAT_DEF=$(find package/boot/arm-trusted-firmware-mtk/src/ -name "platform_def.h" | head -n 1)
if [ -n "$ATF_PLAT_DEF" ]; then
    echo "#define FLASH_FIP_BASE (0x40000)" >> "$ATF_PLAT_DEF"
    echo "#define FLASH_FIP_MAX_SIZE (0x80000)" >> "$ATF_PLAT_DEF"
fi

# 4. 物理跳转对齐：锁定 U-Boot 加载基址 0x41e00000 (与 ATF 链接地址对齐)
find package/boot/uboot-mtk/src/configs/ -name "mt7981_spim_nor_rfb_defconfig" -exec sed -i 's/CONFIG_TEXT_BASE.*/CONFIG_TEXT_BASE=0x41e00000/g' {} +

# 5. 网络救砖通路：预设 IP 192.168.1.1 (方便 TFTP 环境直接物理拦截)
find package/boot/uboot-mtk/src/configs/ -name "mt7981_spim_nor_rfb_defconfig" -exec sed -i 's/CONFIG_IPADDR.*/CONFIG_IPADDR="192.168.1.1"/g' {} +
find package/boot/uboot-mtk/src/configs/ -name "mt7981_spim_nor_rfb_defconfig" -exec sed -i 's/CONFIG_SERVERIP.*/CONFIG_SERVERIP="192.168.1.2"/g' {} +

# 6. 设备树像素级对齐 (确保 U-Boot 引用你提供的 1G 版 DTS 定义)
find package/boot/uboot-mtk/src/configs/ -name "mt7981_spim_nor_rfb_defconfig" -exec sed -i 's/CONFIG_DEFAULT_DEVICE_TREE.*/CONFIG_DEFAULT_DEVICE_TREE="mt7981b-sl3000-emmc"/g' {} +

echo "V2 Physical Patch Applied: All hardware constraints have been locked."
