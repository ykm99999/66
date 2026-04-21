#!/bin/bash
# build_kernel.sh - 构建司络 SL3000 全家桶救砖固件 (32MB)
# 放置于仓库根目录
# 作者：你 + Qwen 💡
set -e

echo "============================================"
echo "🔧 司络 SL3000 救砖全家桶构建脚本 (32MB)"
echo "芯片: MT7981B + MT7976CN | DDR4 + eMMC"
echo "输出: sl3000-rescue-32m.bin"
echo "============================================"

# === 配置区 ===
OUT_DIR="output"
IMMORTALWRT_DIR="immortalwrt"
UBOOT_DIR="u-boot"
ATF_DIR="arm-trusted-firmware"
CONFIG_DIR="888"
PREBUILT_DIR="prebuilt"

BOARD_NAME="sl3000"
TARGET_SIZE=$((32 * 1024 * 1024))  # 32MB

mkdir -p "$OUT_DIR"

# 检查 prebuilt 必需文件
if [ ! -f "$PREBUILT_DIR/bl2-emmc-ddr4.bin" ]; then
    echo "❌ 错误: $PREBUILT_DIR/bl2-emmc-ddr4.bin 不存在！请放入 Preloader。"
    exit 1
fi
if [ ! -f "$PREBUILT_DIR/factory_orig.bin" ]; then
    echo "❌ 错误: $PREBUILT_DIR/factory_orig.bin 不存在！请放入校准数据。"
    exit 1
fi

# === 1. 编译 ImmortalWrt ===
echo "📦 步骤 1/4: 编译 ImmortalWrt (生成 sysupgrade.itb)..."
cd "$IMMORTALWRT_DIR"

# 应用配置
cp "../$CONFIG_DIR/sl3000.config" .config
make defconfig

# 替换 DTS
DTS_DST="target/linux/mediatek/mt7981/files/arch/arm64/boot/dts/mediatek/mt7981b-sl3000-emmc.dts"
cp "../$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$DTS_DST"

# 编译（使用全部 CPU 核心）
make -j$(nproc) V=s

# 查找 itb
ITB_FILE=$(find bin/targets/mediatek/mt7981 -name "*sysupgrade.itb" | head -n1)
if [ ! -f "$ITB_FILE" ]; then
    echo "❌ 未找到 sysupgrade.itb，请检查编译是否成功。"
    exit 1
fi
cp "$ITB_FILE" "../$OUT_DIR/kernel.itb"
echo "✅ 内核镜像已保存至 $OUT_DIR/kernel.itb"
cd ..

# === 2. 编译 ATF ===
echo "📦 步骤 2/4: 编译 ARM Trusted Firmware (ATF)..."
cd "$ATF_DIR"
make -j$(nproc) \
    PLAT=mt7981 \
    ARCH=aarch64 \
    CROSS_COMPILE=aarch64-openwrt-linux-musl- \
    DEBUG=0 \
    bl31
cp build/mt7981/release/bl31.bin "../$OUT_DIR/"
cd ..

# === 3. 编译 U-Boot 并打包 FIP ===
echo "📦 步骤 3/4: 编译 U-Boot 并生成 FIP..."
cd "$UBOOT_DIR"

# 使用你的板级配置（假设 mk 文件可作为 defconfig 基础）
# 若已有 sl3000_defconfig，可跳过；否则需手动创建
if [ ! -f "configs/sl3000_defconfig" ]; then
    echo "⚠️ 注意: configs/sl3000_defconfig 不存在，尝试使用通用 mediatek 配置"
    make mediatek_mt7981_defconfig
else
    make sl3000_defconfig
fi

make -j$(nproc) CROSS_COMPILE=aarch64-openwrt-linux-musl-

# 编译 fiptool（若未存在）
if [ ! -f tools/fiptool ]; then
    make -C tools fiptool
fi

# 创建 FIP
./tools/fiptool create \
    --tb-fw ../$OUT_DIR/bl31.bin \
    --scp-fw u-boot.bin \
    ../$OUT_DIR/bl31-uboot-emmc-ddr4.fip

cd ..

# === 4. 合成 32MB 镜像 ===
echo "📦 步骤 4/4: 合成 32MB 救砖镜像..."

IMG="$OUT_DIR/${BOARD_NAME}-rescue-32m.bin"

# 创建 32MB 空镜像
dd if=/dev/zero of="$IMG" bs=1 count=1 seek=$((TARGET_SIZE - 1))

# 写入各段（严格对齐偏移）
dd if="$PREBUILT_DIR/bl2-emmc-ddr4.bin" of="$IMG" conv=notrunc bs=1 seek=0
dd if="$OUT_DIR/bl31-uboot-emmc-ddr4.fip" of="$IMG" conv=notrunc bs=1 seek=$((0x100000))   # 1MB
dd if="$PREBUILT_DIR/factory_orig.bin" of="$IMG" conv=notrunc bs=1 seek=$((0x200000))      # 2MB
dd if="$OUT_DIR/kernel.itb" of="$IMG" conv=notrunc bs=1 seek=$((0x300000))                 # 3MB

echo "🎉 构建成功！救砖镜像位于:"
ls -lh "$IMG"
echo "SHA256: $(sha256sum "$IMG" | cut -d' ' -f1)"

# 可选：生成烧录命令提示
echo ""
echo "💡 烧录建议（通过 UART + mtk_uartboot）:"
echo "   python3 mtk_uartboot/mtkclient.py payload_loader"
echo "   python3 mtk_uartboot/mtkclient.py flash write boot0 $IMG"
