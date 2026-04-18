#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

echo "=== 1. 物理环境自愈：构建 Host 工具链 ==="
cd "$IMMORTAL_DIR"
make tools/install -j$(nproc)

echo "=== 2. 针对 SL3000 (1G+128G) 暴力对齐配置 ==="
# 强制锁定架构，防止回退到 x86
echo "CONFIG_TARGET_mediatek=y" > .config
echo "CONFIG_TARGET_mediatek_mt7981=y" >> .config
echo "CONFIG_TARGET_mediatek_mt7981_DEVICE_sl_3000-emmc=y" >> .config

# 合并你的 8000 行核心配置并强制回答所有提问
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    cat "$WORKSPACE/888/sl3000.config" >> .config
    yes "" | make oldconfig
    make defconfig
fi

echo "=== 3. 编译内核 ITB (1024M 规格) ==="
make target/linux/compile -j$(nproc) V=s

echo "=== 4. 救砖全家桶全链路合成 (32MB 规格) ==="
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)
[ -z "$KERNEL_SRC" ] && { echo "❌ 审计失败：内核未生成"; exit 1; }

cp -v "$KERNEL_SRC" "$PARTS_DIR/kernel.itb"
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"

# 物理合成：32MB 0xFF 底图
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"
# 写入引导 (对齐 DDR4 1G 补丁后的产物)
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=256k seek=1 conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=256k seek=6 conv=notrunc status=none
dd if="$PARTS_DIR/kernel.itb" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none

echo "✅ [物理规格匹配完成] 1G+128G 救砖包已生成。"
