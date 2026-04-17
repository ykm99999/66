#!/bin/bash
set -euo pipefail

# 修复：自动适配 GitHub Actions 物理路径或本地路径
# 如果存在 main-repo 目录则使用它，否则使用当前根目录
if [ -d "${GITHUB_WORKSPACE:-$(pwd)}/main-repo" ]; then
    MAIN_REPO="${GITHUB_WORKSPACE:-$(pwd)}/main-repo"
else
    MAIN_REPO="${GITHUB_WORKSPACE:-$(pwd)}"
fi

OUTPUT_DIR="$MAIN_REPO/output"
PARTS_DIR="$OUTPUT_DIR/parts"

mkdir -p "$OUTPUT_DIR" "$PARTS_DIR"

# ---------- 使用从原厂32.bin提取的引导文件 ----------
echo "=== 使用原厂提取的引导文件 ==="
# 修复：确保路径引用与实际检出路径一致
cp -v "$MAIN_REPO/888/bl2_orig.bin" "$PARTS_DIR/bl2.bin"
cp -v "$MAIN_REPO/888/fip_orig.bin" "$PARTS_DIR/fip.bin"
cp -v "$MAIN_REPO/888/factory_orig.bin" "$PARTS_DIR/factory.bin"

# ---------- 接下来是构建内核与合成逻辑 (延续 2 版修复) ----------
# ... (此处保持之前 2 版中添加的内核处理逻辑)
