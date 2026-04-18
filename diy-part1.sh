#!/bin/bash
set -euo pipefail

# 物理路径溯源：进入正确的源码目录
if [ -d "immortalwrt" ]; then
    cd immortalwrt
else
    echo "❌ 错误：未发现 immortalwrt 源码目录"
    exit 1
fi

echo "=== 执行 Feeds 物理同步 (当前路径: $(pwd)) ==="
chmod +x scripts/feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 确保 888 配置目录物理可达
cd ..
if [ ! -d "888" ]; then
    echo "⚠️ 警告：未发现 888 资源目录"
fi
