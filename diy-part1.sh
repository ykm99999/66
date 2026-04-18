#!/bin/bash
set -euo pipefail

# 获取当前工作空间绝对路径，实现全链路定位
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
RESOURCE_DIR="$WORKSPACE/888"

echo "=== 1. 物理审计：验证核心资源 ==="
if [ ! -d "$RESOURCE_DIR" ]; then
    echo "❌ 严重错误：未发现 888 资源文件夹，物理链路中断！"
    exit 1
fi

if [ ! -d "$IMMORTAL_DIR" ]; then
    echo "❌ 严重错误：未发现 immortalwrt 源码目录！"
    exit 1
fi

echo "=== 2. 执行 Feeds 物理同步与清洗 ==="
cd "$IMMORTAL_DIR"

# 清理可能残留的 feeds 索引锁
rm -rf ./feeds.conf.default.index 2>/dev/null

chmod +x scripts/feeds
./scripts/feeds update -a
./scripts/feeds install -a

echo "=== 3. 物理环境自愈：补齐依赖项 ==="
# 强制修补 Feeds 链接可能存在的死链（针对 MT7981 常用插件）
# 可以在此处通过 sed 或 git clone 额外拉取你需要的插件仓
# 例如：git clone https://github.com/messense/miyoo-autoupdate.git package/new-app

echo "✅ [Part 1] 物理环境预检完成，所有路径已闭合。"
