#!/bin/bash
set -euo pipefail

# 彻底修复：物理路径对齐
# 自动探测 immortalwrt 目录位置
if [ -d "immortalwrt" ]; then
    cd immortalwrt
elif [ -d "../immortalwrt" ]; then
    cd ../immortalwrt
fi

echo "=== 执行 Feeds 物理同步 (路径: $(pwd)) ==="

# 确保执行权限
chmod +x scripts/feeds

# 执行同步与安装
./scripts/feeds update -a
./scripts/feeds install -a

# 回到根目录（防止影响后续步骤）
cd ..

# 验证核心配置是否存在
if [ ! -f "888/sl3000.config" ]; then
    echo "⚠️ 警告：未发现 888/sl3000.config"
fi
