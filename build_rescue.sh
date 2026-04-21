#!/bin/bash
# =====================================================
# 🛠️  救砖全家桶合成脚本 build_rescue.sh
# 功能: 自动拉取 BL2, FIP, Kernel，并合成32M烧录包
# 作者: 你的AI战友 (基于Qwen)
# =====================================================

set -euxo pipefail

echo "🚀 开始构建 SL3000 救砖全家桶..."

# -------------------------------
# 🔧 配置区 (你可以根据需要修改)
# -------------------------------
OUTPUT_FILE="sl3000_rescue_$(date +%Y%m%d).bin"
FULL_SIZE_BYTES=$((32 * 1024 * 1024)) # 32MB
KERNEL_PATH="immortalwrt/bin/targets/mediatek/filogic/" # ⚠️ 请检查并修正此路径！
CONFIG_DIR="888"

# 偏移地址 (Bytes)
declare -A OFFSETS=(
    ["BL2"]=0
    ["FIP"]=1048576     # 0x100000 = 1M
    ["KERNEL"]=2097152  # 0x200000 = 2M
)

# -------------------------------
# 📂 准备工作
# -------------------------------
# 创建临时输出目录
mkdir -p prebuilt output

# 创建一个填充为 0xFF 的空白镜像
echo "📝 创建 ${FULL_SIZE_BYTES} 字节的空白模板..."
python3 -c "
with open('$OUTPUT_FILE', 'wb') as f:
    f.write(b'\xFF' * $FULL_SIZE_BYTES)
"

# -------------------------------
# 🔨 核心步骤 1: 合成 FIP 文件 (ATF + U-Boot)
# -------------------------------
echo "🔨 正在合成 FIP (ATF + U-Boot)..."
FIP_OUTPUT="prebuilt/bl31-uboot-emmc-ddr4.fip"

# 检查必要的源文件
if [[ ! -f "arm-trusted-firmware/build/mt7981/release/bl31.bin" ]]; then
    echo "❌ 错误: 找不到 ATF (bl31.bin)。请确保 arm-trusted-firmware 已正确编译。"
    exit 1
fi

if [[ ! -f "u-boot/u-boot.bin" ]]; then
    echo "❌ 错误: 找不到 U-Boot (u-boot.bin)。请确保 u-boot 已正确编译。"
    exit 1
fi

# 使用 U-Boot 自带的工具合成 FIP (这是最关键的一步!)
./u-boot/tools/make_fip.sh \
    --soc mt7981 \
    --out "$FIP_OUTPUT" \
    --bl31 "arm-trusted-firmware/build/mt7981/release/bl31.bin" \
    --uboot "u-boot/u-boot.bin"

if [[ $? -ne 0 ]]; then
    echo "❌ 错误: make_fip.sh 执行失败，请检查脚本权限和依赖。"
    exit 1
fi

echo "✅ FIP 文件已生成: $FIP_OUTPUT"

# -------------------------------
# 📦 核心步骤 2: 收集所有组件并写入
# -------------------------------
echo "📦 正在将所有组件写入烧录包..."

declare -A FILES=(
    ["BL2"]="mtk_uartboot/bl2-emmc-ddr4.bin"
    ["FIP"]="$FIP_OUTPUT"
    ["KERNEL"]=$(find "$KERNEL_PATH" -name "sysupgrade.itb" | head -n 1)
)

for component in "${!FILES[@]}"; do
    file_path="${FILES[$component]}"
    offset="${OFFSETS[$component]}"
    
    if [[ ! -f "$file_path" ]]; then
        echo "❌ 错误: 找不到 $component 文件: $file_path"
        exit 1
    fi
    
    echo "  ➕ 写入 $component -> 偏移 0x$(printf '%X' $offset)"
    dd if="$file_path" of="$OUTPUT_FILE" seek=$offset conv=notrunc bs=1 status=none
done

# -------------------------------
# 🎉 完成
# -------------------------------
mv "$OUTPUT_FILE" output/
echo "🎉 救砖全家桶构建成功！"
echo "📦 文件路径: $(pwd)/output/$OUTPUT_FILE"
echo "📏 文件大小: $(ls -lh output/$OUTPUT_FILE | awk '{print $5}')"
echo "💡 现在你可以使用编程器或串口工具烧录这个文件到设备的 eMMC 0x0 地址了！"
