#!/bin/bash
set -euo pipefail

# ========== 延续 1 版：路径与环境变量定义 (原文照抄) ==========
WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware

# ========== 准备源码与环境 ==========
echo "=== Preparing ImmortalWrt Source ==="
cp -r $SOURCE_DIR/immortalwrt/. $IMMORTALWRT_BUILD/
cd $IMMORTALWRT_BUILD

# ========== V2 物理修复注入 (Feeds 之前) ==========
echo "=== 物理清理内存限制补丁 ==="
find target/linux/mediatek/patches-6.6/ -name "*mt7981-256m-dram*" -delete
find target/linux/mediatek/patches-6.6/ -name "*mt7981-512m-dram*" -delete

./scripts/feeds update -a && ./scripts/feeds install -a

# ========== 注入设备定义 (原文照抄) ==========
cp -v $CONFIG_DIR/$DTS_NAME target/linux/mediatek/dts/
cp -v $CONFIG_DIR/sl3000.config .config

# ========== V2 底层源码像素级修复 (200MHz/1G/256K) ==========
echo "=== 修正底层 Bootloader 物理参数 ==="
# 1. 串口 200MHz 锁定 (解决乱码)
UBOOT_H=$(find package/boot/uboot-mtk/src/include/configs/ -name "mt7981.h")
sed -i 's/#define CFG_SYS_NS16550_CLK.*/#define CFG_SYS_NS16550_CLK 200000000/g' "$UBOOT_H"

# 2. 1G 内存返回与 256K 偏移锁定
ATF_EMICFG=$(find package/boot/arm-trusted-firmware-mtk/src/ -name "emicfg.c")
ATF_PLAT_DEF=$(find package/boot/arm-trusted-firmware-mtk/src/ -name "platform_def.h")

sed -i 's/return 0x20000000/return 0x40000000/g' "$ATF_EMICFG"
sed -i '/#define FLASH_FIP_BASE/d' "$ATF_PLAT_DEF"
sed -i '/#define FLASH_FIP_MAX_SIZE/d' "$ATF_PLAT_DEF"
echo "#define FLASH_FIP_BASE (0x40000)" >> "$ATF_PLAT_DEF"
echo "#define FLASH_FIP_MAX_SIZE (0x80000)" >> "$ATF_PLAT_DEF"

# ========== 核心编译环节 (防止 5 分钟闪退) ==========
echo "=== 开始物理编译 (此过程预计 40-60 分钟) ==="
make defconfig

# 强制编译核心组件，失败立即退出
make package/boot/arm-trusted-firmware-mtk/compile V=s -j$(nproc)
make package/boot/uboot-mtk/compile V=s -j$(nproc)
make target/linux/compile V=s -j$(nproc)
make package/base-files/compile V=s -j$(nproc)

# 执行最终镜像生成
make V=s -j$(nproc)

# ========== 产物物理抓取 ==========
echo "=== 抓取产物到 output 目录 ==="
find bin/targets/mediatek/filogic/ -type f -name "*bl2*" -exec cp -v {} $OUTPUT_DIR/atf/ \;
find bin/targets/mediatek/filogic/ -type f -name "*fip*" -exec cp -v {} $OUTPUT_DIR/uboot/ \;
find bin/targets/mediatek/filogic/ -type f \( -name "*sysupgrade.bin" -o -name "*itb" \) -exec cp -v {} $OUTPUT_DIR/firmware/ \;
