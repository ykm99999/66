#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

cd "$IMMORTAL_DIR"

echo "=== 1. 物理环境自愈：补齐 Host 工具链 ==="
make tools/install -j$(nproc) || make tools/install -j1 V=s

echo "=== 2. DTS 像素级注入：定义 32MB SPI 分区表 ==="
# 针对 SL3000 的物理 DTS 路径
DTS_FILE="target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
if [ -f "$DTS_FILE" ]; then
    # 物理锁定：bl2(1M), fip(1M), factory(1M), firmware(29M)
    sed -i '/&spi0 {/,/};/c\&spi0 {\n\tstatus = "okay";\n\tflash@0 {\n\t\tcompatible = "jedec,spi-nor";\n\t\treg = <0>;\n\t\tspi-max-frequency = <52000000>;\n\t\tpartitions {\n\t\t\tcompatible = "fixed-partitions";\n\t\t\t#address-cells = <1>;\n\t\t\t#size-cells = <1>;\n\t\t\tpartition@0 { label = "bl2"; reg = <0x000000 0x100000>; read-only; };\n\t\t\tpartition@100000 { label = "fip"; reg = <0x100000 0x100000>; read-only; };\n\t\t\tpartition@200000 { label = "factory"; reg = <0x200000 0x100000>; read-only; };\n\t\t\tpartition@300000 { label = "firmware"; reg = <0x300000 0x1D00000>; };\n\t\t};\n\t};\n};' "$DTS_FILE"
    echo "✅ DTS 物理分区表注入成功"
fi

echo "=== 3. 物理降维打击：粉碎配置冲突 ==="
rm -f .config && touch .config
# 强制锁定架构，剔除所有 x86 干扰
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    grep -v "CONFIG_TARGET_" "$WORKSPACE/888/sl3000.config" >> .config
    # 阻断交互：oldconfig 配合 /dev/null 彻底消灭弹窗
    make oldconfig </dev/null
    make defconfig
fi

echo "=== 4. 执行内核构建 (1G DDR4 规格锁定) ==="
make target/linux/compile -j$(nproc) V=s

echo "=== 5. 救砖镜像物理合成 (32MB SPI) ==="
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)
[ -z "$KERNEL_SRC" ] && { echo "❌ 审计失败：内核未生成"; exit 1; }

# 按物理地址偏移精准 dd 填充
RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=1 seek=$((0x100000)) conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=1 seek=$((0x200000)) conv=notrunc status=none
dd if="$KERNEL_SRC" of="$RESCUE_BIN" bs=1 seek=$((0x300000)) conv=notrunc status=none

echo "✅ [全链路闭合] 1G+128G 规格救砖镜像合成成功：$RESCUE_BIN"
