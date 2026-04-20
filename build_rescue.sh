#!/bin/bash
# build_rescue.sh - SL3000 救砖固件本地全自动构建脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# 基础路径
ROOT_DIR=$(pwd)
CONFIG_DIR="$ROOT_DIR/888"
OUTPUT_DIR="$ROOT_DIR/output"
OWRT_DIR="$ROOT_DIR/immortalwrt"

mkdir -p "$OUTPUT_DIR"

# ========== 环境检查 ==========
log_step "检查构建环境..."
if ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
    log_error "未找到 aarch64-linux-gnu-gcc，请安装交叉编译工具链。"
    exit 1
fi

if [ "$(readlink /bin/sh)" != "bash" ]; then
    log_warn "/bin/sh 未指向 bash，OpenWrt 预检查可能失败。"
    log_warn "请执行: sudo ln -sf /bin/bash /bin/sh"
    read -p "是否继续？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

export CONFIG_SHELL=/bin/bash

# 检查 888/ 目录及必需文件
if [ ! -d "$CONFIG_DIR" ]; then
    log_error "未找到 888/ 配置目录！"
    exit 1
fi

for file in sl3000.config mt7981b-sl3000-emmc.dts mt7981_sl3000.mk \
            bl2_orig.bin fip_orig.bin factory_orig.bin; do
    if [ ! -f "$CONFIG_DIR/$file" ]; then
        log_error "缺失文件: $CONFIG_DIR/$file"
        exit 1
    fi
done

# ========== 准备 OpenWrt 源码 ==========
log_step "检查 OpenWrt 源码..."
if [ ! -d "$OWRT_DIR/.git" ]; then
    log_warn "immortalwrt 源码不存在，正在克隆..."
    git clone --depth 1 https://github.com/immortalwrt/immortalwrt.git "$OWRT_DIR"
else
    log_info "immortalwrt 源码已存在，跳过克隆。"
fi

# ========== 应用配置 ==========
log_step "应用设备配置文件..."
cd "$OWRT_DIR"
cp "$CONFIG_DIR/sl3000.config" .config
cp "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp "$CONFIG_DIR/mt7981_sl3000.mk" target/linux/mediatek/image/filogic.mk

# ========== 更新 feeds ==========
log_step "更新 feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# ========== 准备内核源码并复制 DTS ==========
log_step "准备内核源码..."
make defconfig
make target/linux/prepare V=s

# 定位内核构建目录
LINUX_DIR=$(find build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic -maxdepth 1 -type d -name "linux-*" | head -1)
if [ -z "$LINUX_DIR" ]; then
    log_error "未找到内核源码目录！"
    exit 1
fi
log_info "内核源码位于: $LINUX_DIR"

# 复制 DTS 到内核树
cp "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$LINUX_DIR/arch/arm64/boot/dts/"
log_info "DTS 已复制到内核源码树。"

# ========== 编译 ==========
log_step "开始编译 OpenWrt (单线程，耗时较长)..."
make -j1 V=s

# ========== 提取 sysupgrade.itb ==========
log_step "提取 sysupgrade.itb..."
ITB_FILE=$(find bin/targets/mediatek/filogic -name "*-sysupgrade.itb" | head -1)
if [ -z "$ITB_FILE" ]; then
    log_error "未找到 sysupgrade.itb，编译可能失败。"
    exit 1
fi
cp "$ITB_FILE" "$OUTPUT_DIR/sysupgrade.itb"
log_info "内核镜像已复制到 $OUTPUT_DIR/sysupgrade.itb"

# ========== 合成 32MB 烧录包 ==========
log_step "合成最终 32MB 救砖固件..."
cd "$OUTPUT_DIR"
FINAL_BIN="sl3000-rescue-32mb.bin"

# 复制原始 bin 文件
cp "$CONFIG_DIR/bl2_orig.bin" bl2-emmc-ddr3.bin
cp "$CONFIG_DIR/fip_orig.bin" bl31-uboot-emmc-ddr3.fip
cp "$CONFIG_DIR/factory_orig.bin" factory_orig.bin

# 创建 32MB 全 0xFF 文件（修复 dd 语法）
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$FINAL_BIN"

# 写入各分区
echo "写入 BL2 @ 0M"
dd if=bl2-emmc-ddr3.bin of="$FINAL_BIN" conv=notrunc status=none

echo "写入 FIP @ 1M"
dd if=bl31-uboot-emmc-ddr3.fip of="$FINAL_BIN" bs=1M seek=1 conv=notrunc status=none

echo "写入 Factory @ 2M"
dd if=factory_orig.bin of="$FINAL_BIN" bs=1M seek=2 conv=notrunc status=none

echo "写入 Kernel @ 3M"
dd if=sysupgrade.itb of="$FINAL_BIN" bs=1M seek=3 conv=notrunc status=none

log_info "✅ 构建完成！输出文件：$OUTPUT_DIR/$FINAL_BIN"
log_info "文件大小：$(du -h "$FINAL_BIN" | cut -f1)"
