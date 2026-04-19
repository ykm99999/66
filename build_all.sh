#!/bin/bash
# build_all.sh - 完整构建：内核编译 + 合成固件

set -e

echo "=== SL3000 救砖固件完整构建 ==="

# 步骤 1：编译内核
if [ -f "./build_kernel.sh" ]; then
    ./build_kernel.sh
else
    echo "错误：未找到 build_kernel.sh"
    exit 1
fi

# 步骤 2：合成固件
if [ -f "./assemble_firmware.sh" ]; then
    ./assemble_firmware.sh
else
    echo "错误：未找到 assemble_firmware.sh"
    exit 1
fi

echo "✅ 全部完成！固件位于 output/sl3000-rescue-32mb.bin"
