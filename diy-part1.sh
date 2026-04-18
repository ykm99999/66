#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
# 自动定位主仓库根目录
ROOT_DIR="$WORKSPACE"
[ -d "$WORKSPACE/main-repo" ] && ROOT_DIR="$WORKSPACE/main-repo"

OUTPUT_DIR="$WORKSPACE/output"

echo "=== 救砖全家桶：准备构建环境 (3版) ==="

# 1. 物理目录结构初始化
# 修复：确保所有产物目录一次性建立，防止后续编译脚本因目录缺失报错
mkdir -p "$OUTPUT_DIR"/{atf,uboot,parts,logs}

# 2. 核心交叉编译器审计
if ! which aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "❌ 错误：未找到 aarch64-linux-gnu-gcc。请在 CI 中安装 gcc-aarch64-linux-gnu"
    exit 1
fi

# 3. 补全：内核编译工具链审计
# 彻底解决编译失败的关键：检查构建 ITB 和内核必备的 host 工具
MISSING_TOOLS=()
for tool in dtc bison flex gawk make python3; do
    if ! which $tool >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "❌ 错误：物理环境缺失构建工具: ${MISSING_TOOLS[*]}"
    echo "请执行: sudo apt-get install -y device-tree-compiler bison flex gawk build-essential"
    exit 1
fi

# 4. 源码物理布局审计 (支持内核构建)
# 修复：增加对 immortalwrt (内核源码) 和 888 (配置/引导) 文件夹的硬性检查
CHECK_DIRS=(
    "arm-trusted-firmware"
    "u-boot"
    "immortalwrt"
    "888"
)

for dir in "${CHECK_DIRS[@]}"; do
    if [ ! -d "$WORKSPACE/$dir" ] && [ ! -d "$ROOT_DIR/$dir" ]; then
        echo "❌ 物理审计失败：未在工作空间找到 $dir 源码目录"
        exit 1
    fi
done

# 5. 配置文件预审
# 确保你的 8000 行配置 sl3000.config 物理存在
CONFIG_PATH=$(find "$WORKSPACE" -name "sl3000.config" | head -n 1)
if [ -z "$CONFIG_PATH" ]; then
    echo "⚠️ 警告：未发现 sl3000.config，内核构建将使用默认配置。"
else
    echo "✅ 发现配置文件: $CONFIG_PATH"
fi

echo "✅ 物理环境审计通过：所有源码、工具链、配置文件已就绪。"
