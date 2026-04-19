#!/bin/bash
# build_kernel.sh - 单独构建 SL3000 内核 (sysupgrade.itb)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

ROOT_DIR=$(pwd)
CONFIG_DIR="$ROOT_DIR/888"
OWRT_DIR="$ROOT_DIR/immortalwrt"
OUTPUT_DIR="$ROOT_DIR/output"

mkdir -p "$OUTPUT_DIR"

# 检查配置文件
if [ ! -d "$CONFIG_DIR" ]; then
    log_error "未找到 888/ 目录"
    exit 1
fi

for file in sl3000.config mt7981b-sl3000-emmc.dts mt7981_sl3000.mk; do
    if [ ! -f "$CONFIG_DIR/$file" ]; then
        log_error "缺失: $CONFIG_DIR/$file"
        exit 1
    fi
done

# 检查 OpenWrt 源码
if [ ! -d "$OWRT_DIR/.git" ]; then
    log_warn "OpenWrt 源码不存在，正在克隆 immortalwrt..."
    git clone --depth 1 https://github.com/immortalwrt/immortalwrt.git "$OWRT_DIR"
fi

log_info "配置 OpenWrt 编译环境..."
cd "$OWRT_DIR"

# 应用配置文件
cp "$CONFIG_DIR/sl3000.config" .config
cp "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp "$CONFIG_DIR/mt7981_sl3000.mk" target/linux/mediatek/image/

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

make defconfig

log_info "开始编译内核与 rootfs（预计耗时较长）..."
make -j$(nproc) V=s

# 查找生成的 sysupgrade.itb
ITB_FILE=$(find bin/targets/mediatek/filogic -name "*-sysupgrade.itb" | head -1)
if [ -z "$ITB_FILE" ]; then
    log_error "未找到 sysupgrade.itb，编译可能失败"
    exit 1
fi

cp "$ITB_FILE" "$OUTPUT_DIR/sysupgrade.itb"
log_info "✅ sysupgrade.itb 已生成并复制到 $OUTPUT_DIR/"
