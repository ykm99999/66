#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
IMMORTAL_DIR="$WORKSPACE/immortalwrt"
OUTPUT_DIR="$WORKSPACE/output"
REPO_888="$WORKSPACE/888"

cd "$IMMORTAL_DIR"

echo "=== 1. 物理基因注入：同步 888 三件套 ==="
# [1] 注入 Device 定义 (MK)
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"
if [ -f "$REPO_888/mt7981_sl3000.mk" ]; then
    # 清理旧定义，物理追加仓库新定义
    sed -i '/Device\/sl_3000-emmc/,/endef/d' "$FILOGIC_MK"
    cat "$REPO_888/mt7981_sl3000.mk" >> "$FILOGIC_MK"
    echo "✅ Device MK 注入完成"
fi

# [2] 注入设备树 (DTS)
# 物理对齐：确保文件名与 MK 中的 DEVICE_DTS 像素级匹配
TARGET_DTS="target/linux/mediatek/dts/mt7981b-sl-3000-emmc.dts"
if [ -f "$REPO_888/mt7981b-sl3000-emmc.dts" ]; then
    cp -f "$REPO_888/mt7981b-sl3000-emmc.dts" "$TARGET_DTS"
    echo "✅ DTS 物理覆盖完成"
fi

# [3] 注入配置母本 (.config)
if [ -f "$REPO_888/sl3000.config" ]; then
    cp -f "$REPO_888/sl3000.config" .config
    # 物理封印：强制开启 BUILDBOT 模式，严禁交互
    echo "CONFIG_BUILDBOT=y" >> .config
    echo "✅ Config 注入完成"
fi

echo "=== 2. 物理致盲：切断 mconf 弹窗逻辑 ==="
# 物理爆破：即便配置有冲突，也让系统以为不支持图形界面，直接报错而不是卡死
if [ -f "scripts/config/mconf-cfg.sh" ]; then
    echo "exit 1" > scripts/config/mconf-cfg.sh
    chmod +x scripts/config/mconf-cfg.sh
fi

echo "=== 3. 物理构建：工具链与配置补全 ==="
# 预先处理 Feeds
./scripts/feeds update -a && ./scripts/feeds install -a

# 执行非交互式配置补全
# 使用 /dev/null 强制 oldconfig 自动选择默认项
make oldconfig </dev/null
make defconfig

echo "=== 4. 物理编译：内核与固件 ==="
# 加上 CONF_DEFAULT=1 作为双重保险
make target/linux/compile -j$(nproc) V=s CONF_DEFAULT=1

echo "=== 5. 救砖包物理合成 (32MB SPI) ==="
mkdir -p "$OUTPUT_DIR"
KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)

if [ -z "$KERNEL_SRC" ]; then
    echo "❌ 物理审计失败：未找到编译生成的内核镜像"
    exit 1
fi

RESCUE_BIN="$OUTPUT_DIR/rescue-32.bin"
# 创建 32M 纯净空白区 (0xFF 填充)
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$RESCUE_BIN"
# 物理拼接：BL2(0) -> FIP(1M) -> Factory(2M) -> Firmware(3M)
dd if="$REPO_888/bl2_orig.bin" of="$RESCUE_BIN" bs=1 conv=notrunc status=none
dd if="$REPO_888/fip_orig.bin" of="$RESCUE_BIN" bs=1 seek=$((0x100000)) conv=notrunc status=none
dd if="$REPO_888/factory_orig.bin" of="$RESCUE_BIN" bs=1 seek=$((0x200000)) conv=notrunc status=none
dd if="$KERNEL_SRC" of="$RESCUE_BIN" bs=1 seek=$((0x300000)) conv=notrunc status=none

echo "✅ 构建链路已物理闭合，rescue-32.bin 已生成。"
