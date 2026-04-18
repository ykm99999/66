#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理环境自愈：构建 Host 工具链 ==="
cd "$IMMORTAL_DIR"
# 预先构建基础工具，确保 bison/m4 路径正确
make tools/install -j$(nproc)

echo "=== 2. 配置像素级对齐 (彻底消除交互) ==="
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    cp -f "$WORKSPACE/888/sl3000.config" .config
    
    # 彻底解决：使用 yes 命令强制接受所有默认配置项，严禁弹出 menuconfig
    # 这是处理“旧配置配新源码”最暴力且有效的物理手段
    yes "" | make oldconfig
    
    # 再次加固
    make defconfig
else
    echo "❌ 找不到配置文件"
    exit 1
fi

echo "=== 3. 编译内核 ITB ==="
make target/linux/compile -j$(nproc) V=s

echo "=== 4. 全链路合成镜像 ==="
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)
[ -z "$KERNEL_SRC" ] && { echo "❌ 未生成 ITB 文件"; exit 1; }

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 物理合成 (32MB 0xFF 填充)
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [全链路溯源完成] 救砖包已生成！"
