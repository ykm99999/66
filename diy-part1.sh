#!/bin/bash
set -euo pipefail

# 路径变量审计
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
REPO_888="$WORKSPACE/888"

cd "$IMMORTAL_DIR"

echo "=== 1. 物理注入：锁定 sl3000.config 为全局母本 ==="
# 物理压制：将你的 8000 行配置强行覆盖内核与全局构建默认值
if [ -f "$REPO_888/sl3000.config" ]; then
    cp -f "$REPO_888/sl3000.config" .config
    # 强制启用非交互模式，防止卡死
    echo "CONFIG_BUILDBOT=y" >> .config
    echo "✅ 配置母本物理注入成功"
fi

echo "=== 2. 物理注入：DTS 地图物理对齐 ==="
# 物理映射：将仓库 DTS 强行植入 mediatek 架构目录
# 必须确保文件名与后续 mk 文件中的 DEVICE_DTS 像素级对齐
USER_DTS="$REPO_888/mt7981b-sl3000-emmc.dts"
TARGET_DTS_DIR="target/linux/mediatek/dts"

if [ -f "$USER_DTS" ]; then
    cp -f "$USER_DTS" "$TARGET_DTS_DIR/mt7981b-sl-3000-emmc.dts"
    echo "✅ DTS 物理覆盖完成: mt7981b-sl-3000-emmc.dts"
fi

echo "=== 3. 物理注入：mk 准入名单重构 ==="
# 物理重写：直接使用你仓库的 .mk 定义替换底层 filogic.mk 中的 sl_3000 块
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
USER_MK="$REPO_888/mt7981_sl3000.mk"

if [ -f "$USER_MK" ]; then
    echo "正在执行底层 Makefile 手术..."
    # 物理清理：删除源码中可能存在的同名定义块
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    # 物理追加：将你仓库的定义直接注入底册
    cat "$USER_MK" >> "$FILOGIC_MK"
    echo "✅ filogic.mk 物理补丁完成"
fi

echo "=== 4. 物理致盲：封印 mconf 弹窗总闸 ==="
# 最后的防线：即便配置有误，也严禁弹窗卡死
if [ -f "scripts/config/mconf-cfg.sh" ]; then
    echo "exit 1" > scripts/config/mconf-cfg.sh
    chmod +x scripts/config/mconf-cfg.sh
    echo "✅ 弹窗总闸已物理切断"
fi
