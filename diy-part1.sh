#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"

echo "=== 救砖全家桶：准备构建环境 (2版) ==="

# 修复：增加 parts 目录以兼容后续 dd 合成逻辑
mkdir -p "$OUTPUT_DIR"/{atf,uboot,parts}

# 物理环境审计：检查交叉编译器
if ! which aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "❌ 错误：未找到 aarch64-linux-gnu-gcc (请在 GitHub Actions 中安装 gcc-aarch64-linux-gnu)"
    exit 1
fi

# 物理环境审计：检查源码目录是否存在
# 修复：根据你之前的描述，分支目录可能直接位于 $WORKSPACE 下，此处做了兼容性逻辑
[ -d "$MAIN_REPO/arm-trusted-firmware" ] || [ -d "$WORKSPACE/arm-trusted-firmware" ] || { echo "❌ 缺少 arm-trusted-firmware 源码"; exit 1; }
[ -d "$MAIN_REPO/u-boot" ] || [ -d "$WORKSPACE/u-boot" ] || { echo "❌ 缺少 u-boot 源码"; exit 1; }
[ -d "$MAIN_REPO/mtk_uartboot" ] || [ -d "$WORKSPACE/mtk_uartboot" ] || { echo "❌ 缺少 mtk_uartboot 源码"; exit 1; }

# 修复：额外检查内核构建所需的 dtc 工具（设备树编译器）
if ! which dtc >/dev/null 2>&1; then
    echo "⚠️ 警告：未找到 dtc，内核构建可能会失败。建议执行: sudo apt-get install device-tree-compiler"
fi

echo "✅ 环境检查通过：交叉编译器及源码目录准备就绪"
