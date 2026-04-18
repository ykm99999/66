#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"

cd "$IMMORTAL_DIR"

echo "=== 1. 物理环境自愈：真空构建工具链 ==="
# 关键修复：暂时移除所有配置文件，防止 make tools 触发交互
rm -f .config
# 使用 --silent 减少日志冗余，直接构建工具链
make tools/install -j$(nproc) BUILD_LOG=0 || make tools/install -j1 V=s

echo "=== 2. 物理注入配置 (1G RAM + 128G eMMC) ==="
# 重新创建全新的物理锁定配置
cat <<EOF > .config
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y
EOF

# 物理清洗 8000 行配置并注入
if [ -f "$WORKSPACE/888/sl3000.config" ]; then
    grep -v "CONFIG_TARGET_" "$WORKSPACE/888/sl3000.config" >> .config
fi

# 核心补丁：使用命令重定向粉碎交互需求
# - oldconfig 配合 /dev/null 会自动对所有新选项选择默认值
# - defconfig 会自动补全依赖
make oldconfig </dev/null
make defconfig

echo "=== 3. DTS 物理分区表定义 (32MB SPI) ==="
DTS_FILE="target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
if [ -f "$DTS_FILE" ]; then
    # 强制注入 1M/1M/1M/29M 分区布局
    sed -i '/&spi0 {/,/};/c\&spi0 {\n\tstatus = "okay";\n\tflash@0 {\n\t\tcompatible = "jedec,spi-nor";\n\t\treg = <0>;\n\t\tspi-max-frequency = <52000000>;\n\t\tpartitions {\n\t\t\tcompatible = "fixed-partitions";\n\t\t\t#address-cells = <1>;\n\t\t\t#size-cells = <1>;\n\t\t\tpartition@0 { label = "bl2"; reg = <0x000000 0x100000>; read-only; };\n\t\t\tpartition@100000 { label = "fip"; reg = <0x100000 0x100000>; read-only; };\n\t\t\tpartition@200000 { label = "factory"; reg = <0x200000 0x100000>; read-only; };\n\t\t\tpartition@300000 { label = "firmware"; reg = <0x300000 0x1D00000>; };\n\t\t};\n\t};\n};' "$DTS_FILE"
fi

echo "=== 4. 物理编译内核 (1G DDR4) ==="
# 此时配置已绝对锁定，直接开始
make target/linux/compile -j$(nproc) V=s

echo "=== 5. 救砖包物理合成 ==="
mkdir -p "$OUTPUT_DIR"
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)
[ -z "$KERNEL_SRC" ] && exit 1

RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$WORKSPACE/888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$WORKSPACE/888/fip_orig.bin" of="$RESCUE_BIN" bs=1 seek=$((0x100000)) conv=notrunc status=none
dd if="$WORKSPACE/888/factory_orig.bin" of="$RESCUE_BIN" bs=1 seek=$((0x200000)) conv=notrunc status=none
dd if="$KERNEL_SRC" of="$RESCUE_BIN" bs=1 seek=$((0x300000)) conv=notrunc status=none

echo "✅ 构建链路已物理闭合。"
