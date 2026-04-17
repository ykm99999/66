#!/bin/bash
set -euo pipefail

# ==============================================
# 完整 SL3000 固件合成脚本
# 前提：已完成 ATF / U-Boot 编译（救砖全家桶）和 OpenWrt 完整编译
# ==============================================

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
OUTPUT_DIR="$WORKSPACE/output"
PARTS_DIR="$OUTPUT_DIR/parts"

# 分区源文件
BL2_SRC="$OUTPUT_DIR/atf/bl2-1g-nor.bin"
FIP_SRC="$OUTPUT_DIR/uboot/fip-nor.bin"
FACTORY_SRC="$PARTS_DIR/factory.bin"          # 需用户从设备备份
FIRMWARE_SRC="$PARTS_DIR/firmware.bin"        # 将由此脚本生成

# 最终输出
OUTPUT_BIN="$OUTPUT_DIR/Spi-flash-32MB-full.bin"

# 创建必要目录
mkdir -p "$PARTS_DIR"

# ========== 第一步：从 OpenWrt 编译产物提取 kernel + rootfs ==========
echo "=== 提取 Linux 内核与根文件系统 ==="
cd "$IMMORTALWRT_BUILD"

# 查找 vmlinux.bin 或 uImage 位置
KERNEL_ELF=$(find build_dir/target-aarch64_cortex-a53_musl/linux-* -name vmlinux -type f 2>/dev/null | head -1)
if [ -z "$KERNEL_ELF" ]; then
    echo "❌ 找不到内核 ELF 文件 (vmlinux)"
    exit 1
fi
KERNEL_DIR=$(dirname "$KERNEL_ELF")
KERNEL_BIN="$KERNEL_DIR/vmlinux.bin"

# 检查是否已存在 vmlinux.bin，若没有则尝试从 vmlinux 生成
if [ ! -f "$KERNEL_BIN" ]; then
    # 如果存在 arch/arm64/boot/Image 则直接复制
    if [ -f "$KERNEL_DIR/arch/arm64/boot/Image" ]; then
        cp -v "$KERNEL_DIR/arch/arm64/boot/Image" "$KERNEL_BIN"
    else
        # 否则使用 objcopy 将 ELF 转换为原始二进制
        aarch64-linux-gnu-objcopy -O binary "$KERNEL_ELF" "$KERNEL_BIN"
    fi
fi
echo "✅ 内核二进制: $KERNEL_BIN"

# 查找 root.squashfs
ROOTFS_BIN=$(find build_dir/target-aarch64_cortex-a53_musl/root-* -name root.squashfs -type f 2>/dev/null | head -1)
if [ -z "$ROOTFS_BIN" ]; then
    echo "❌ 找不到根文件系统 (root.squashfs)"
    exit 1
fi
echo "✅ 根文件系统: $ROOTFS_BIN"

# 合成 firmware.bin
FIRMWARE_BIN="$PARTS_DIR/firmware.bin"
cat "$KERNEL_BIN" "$ROOTFS_BIN" > "$FIRMWARE_BIN"
echo "✅ 已生成 firmware.bin ($(stat -c%s "$FIRMWARE_BIN") 字节)"

# ========== 第二步：检查 Factory 分区文件 ==========
echo "=== 检查 Factory 分区 ==="
if [ ! -f "$FACTORY_SRC" ]; then
    echo "❌ 缺少 Factory 分区文件: $FACTORY_SRC"
    echo "   请从正常设备备份：dd if=/dev/mtd2 of=/tmp/factory.bin"
    echo "   并将文件放置于 $PARTS_DIR/"
    exit 1
fi
echo "✅ Factory 分区已就绪"

# ========== 第三步：合成 32MB 全镜像 ==========
echo "=== 合成完整 SPI Flash 镜像 ==="
if [ ! -f "$BL2_SRC" ]; then
    echo "❌ 缺少 BL2 文件: $BL2_SRC"
    exit 1
fi
if [ ! -f "$FIP_SRC" ]; then
    echo "❌ 缺少 FIP 文件: $FIP_SRC"
    exit 1
fi

# 创建 32MB 空文件并填充 0xFF
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$OUTPUT_BIN"

# 写入各分区（偏移量参考 MTD 分区表）
# BL2      : 0x00000000
# Config   : 0x00100000 (留空，保持 0xFF)
# Factory  : 0x00180000
# FIP      : 0x00380000
# firmware : 0x00580000

dd if="$BL2_SRC" of="$OUTPUT_BIN" bs=1 conv=notrunc status=none
dd if="$FACTORY_SRC" of="$OUTPUT_BIN" bs=1 seek=$((0x180000)) conv=notrunc status=none
dd if="$FIP_SRC" of="$OUTPUT_BIN" bs=1 seek=$((0x380000)) conv=notrunc status=none
dd if="$FIRMWARE_BIN" of="$OUTPUT_BIN" bs=1 seek=$((0x580000)) conv=notrunc status=none

echo "=========================================="
echo "✅ 完整镜像生成成功！"
echo "   文件: $OUTPUT_BIN"
ls -lh "$OUTPUT_BIN"
echo "=========================================="
