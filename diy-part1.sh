#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"

echo "=== 救砖全家桶：准备构建环境 ==="

mkdir -p "$OUTPUT_DIR"/{atf,uboot}

if ! which aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "❌ 未找到 aarch64-linux-gnu-gcc"
    exit 1
fi

[ -d "$MAIN_REPO/arm-trusted-firmware" ] || { echo "❌ 缺少 arm-trusted-firmware"; exit 1; }
[ -d "$MAIN_REPO/u-boot" ] || { echo "❌ 缺少 u-boot"; exit 1; }
[ -d "$MAIN_REPO/mtk_uartboot" ] || { echo "❌ 缺少 mtk_uartboot"; exit 1; }

echo "✅ 环境检查通过"
