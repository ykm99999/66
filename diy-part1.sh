#!/bin/bash
set -euo pipefail

# 物理路径溯源
if [ -d "immortalwrt" ]; then
    cd immortalwrt
else
    echo "❌ 物理审计失败：未在根目录发现 immortalwrt 源码"
    exit 1
fi

echo "=== 执行 Feeds 物理同步 ==="
chmod +x scripts/feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 回到根目录
cd ..
if [ ! -d "888" ]; then echo "⚠️ 警告：缺少 888 资源文件夹"; fi
