#!/bin/bash
set -euo pipefail

# ========== 1. 核心路径定义 (延续 1 版) ==========
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
DTS_NAME="mt7981b-sl3000-emmc.dts"

mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"

# ========== 2. 物理拉取：锁定 sl3000-full-sync 分支 (彻底解决 128 错误) ==========
echo "=== 正在拉取远程分支源码 ==="
if [ ! -d "$SOURCE_DIR" ]; then
    # 像素级对齐：直接克隆指定分支，不留任何歧义
    git clone --depth 1 -b sl3000-full-sync https://github.com/ykm99999/66 "$SOURCE_DIR"
fi

# 修正物理目录映射：将子目录 immortalwrt 软链接或移动到编译目录
echo "=== 同步编译框架 ==="
if [ -d "$SOURCE_DIR/immortalwrt" ]; then
    cp -r "$SOURCE_DIR/immortalwrt/." "$IMMORTALWRT_BUILD/"
else
    echo "❌ 物理错误：在分支中未找到 immortalwrt 文件夹"
    exit 1
fi

cd "$IMMORTALWRT_BUILD"

# ========== 3. 预热与源码解压 (解决 find 报错) ==========
./scripts/feeds update -a && ./scripts/feeds install -a

# 强制解压，确保 sed 能够物理命中文件
make package/boot/uboot-mtk/prepare V=s
make package/boot/arm-trusted-firmware-mtk/prepare V=s

# ========== 4. 物理参数锁定 (1G/200M/256K) ==========
echo "=== 执行像素级底层参数修复 ==="

# 串口频率修正 (解决 115200 乱码)
find package/boot/uboot-mtk/ -name "mt7981.h" -exec sed -i 's/#define CFG_SYS_NS16550_CLK.*/#define CFG_SYS_NS16550_CLK 200000000/g' {} +

# 内存容量修正 (解决 1024M 识别)
find package/boot/arm-trusted-firmware-mtk/ -name "emicfg.c" -exec sed -i 's/return 0x20000000/return 0x40000000/g' {} +

# 引导偏移修正 (解决 256K 寻址特征码)
PLAT_DEF=$(find package/boot/arm-trusted-firmware-mtk/ -name "platform_def.h" | head -n 1)
if [ -n "$PLAT_DEF" ]; then
    sed -i '/#define FLASH_FIP_BASE/d' "$PLAT_DEF"
    sed -i '/#define FLASH_FIP_MAX_SIZE/d' "$PLAT_DEF"
    echo "#define FLASH_FIP_BASE (0x40000)" >> "$PLAT_DEF"
    echo "#define FLASH_FIP_MAX_SIZE (0x80000)" >> "$PLAT_DEF"
fi

# ========== 5. 注入用户配置 (原文照抄) ==========
cp -v "$CONFIG_DIR/$DTS_NAME" target/linux/mediatek/dts/
cp -v "$CONFIG_DIR/sl3000.config" .config

# ========== 6. 开启物理构建 (核心环节) ==========
echo "=== 开始物理编译 (预计 40-60 分钟) ==="
make defconfig
make package/boot/arm-trusted-firmware-mtk/compile V=s -j$(nproc)
make package/boot/uboot-mtk/compile V=s -j$(nproc)
make V=s -j$(nproc)

# ========== 7. 产物物理抓取 ==========
find bin/targets/mediatek/filogic/ -type f \( -name "*bl2*" -o -name "*fip*" -o -name "*sysupgrade.bin" \) -exec cp -v {} "$OUTPUT_DIR/" \;
