#!/bin/bash
set -euo pipefail

# ========== 延续基础路径 (原文照抄) ==========
WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware

# ========== 准备源码 ==========
echo "=== Preparing ImmortalWrt Source ==="
cp -r $SOURCE_DIR/immortalwrt/. $IMMORTALWRT_BUILD/
cd $IMMORTALWRT_BUILD

# ========== 关键修正：确保 Bootloader 源码已下载 (物理预热) ==========
echo "=== 预热 Bootloader 源码包 ==="
# 强制更新并安装 feeds 以确保 package 目录结构生成
./scripts/feeds update -a && ./scripts/feeds install -a

# 物理诊断：如果找不到文件夹，尝试手动 prepare 源码
make package/boot/uboot-mtk/prepare V=s || true
make package/boot/arm-trusted-firmware-mtk/prepare V=s || true

# ========== V2 物理修复注入 (使用穿透搜索) ==========
echo "=== 修正底层 Bootloader 物理参数 ==="

# 1. 串口 200MHz 锁定
# 理由：改用通配符搜寻，忽略具体的 src/ 层级差异
UBOOT_H=$(find package/boot/uboot-mtk/ -name "mt7981.h" | head -n 1)
if [ -n "$UBOOT_H" ]; then
    sed -i 's/#define CFG_SYS_NS16550_CLK.*/#define CFG_SYS_NS16550_CLK 200000000/g' "$UBOOT_H"
    echo "✅ 已修正 U-Boot 时钟: $UBOOT_H"
else
    echo "⚠️ 警告：未找到 mt7981.h，可能在后续编译中自动解压，跳过此步"
fi

# 2. 1G 内存返回与 256K 偏移锁定
ATF_EMICFG=$(find package/boot/arm-trusted-firmware-mtk/ -name "emicfg.c" | head -n 1)
ATF_PLAT_DEF=$(find package/boot/arm-trusted-firmware-mtk/ -name "platform_def.h" | head -n 1)

if [ -n "$ATF_EMICFG" ]; then
    sed -i 's/return 0x20000000/return 0x40000000/g' "$ATF_EMICFG"
    echo "✅ 已修正 ATF 内存容量: $ATF_EMICFG"
fi

if [ -n "$ATF_PLAT_DEF" ]; then
    sed -i '/#define FLASH_FIP_BASE/d' "$ATF_PLAT_DEF"
    sed -i '/#define FLASH_FIP_MAX_SIZE/d' "$ATF_PLAT_DEF"
    echo "#define FLASH_FIP_BASE (0x40000)" >> "$ATF_PLAT_DEF"
    echo "#define FLASH_FIP_MAX_SIZE (0x80000)" >> "$ATF_PLAT_DEF"
    echo "✅ 已修正 ATF 引导偏移: $ATF_PLAT_DEF"
fi

# ========== 注入 DTS 与配置 (原文照抄) ==========
cp -v $CONFIG_DIR/$DTS_NAME target/linux/mediatek/dts/
cp -v $CONFIG_DIR/sl3000.config .config

# ========== 核心编译环节 (防止闪退) ==========
echo "=== 开始物理编译 ==="
make defconfig
# 针对 SL3000 特性，优先执行一次 Bootloader 完整编译
make package/boot/arm-trusted-firmware-mtk/compile V=s -j$(nproc)
make package/boot/uboot-mtk/compile V=s -j$(nproc)

# 生成完整镜像
make V=s -j$(nproc)

# ========== 产物物理抓取 ==========
find bin/targets/mediatek/filogic/ -type f \( -name "*bl2*" -o -name "*fip*" -o -name "*sysupgrade.bin" \) -exec cp -v {} $OUTPUT_DIR/ \;
