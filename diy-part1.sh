#!/bin/bash
set -euo pipefail

# 物理同步逻辑：确保所有依赖包源码落盘
echo "=== 执行 Feeds 物理同步 ==="
./scripts/feeds update -a
./scripts/feeds install -a

# 确保 888 目录下的配置文件存在
if [ ! -f "888/sl3000.config" ]; then
    echo "⚠️ 警告：未发现 888/sl3000.config，请检查仓库路径。"
fi
