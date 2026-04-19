#!/bin/bash
# build_rescue.sh - SL3000 救砖固件全自动构建脚本
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== SL3000 救砖全家桶构建开始 ===${NC}"

# 基础路径
ROOT_DIR=$(pwd)
OUTPUT_DIR="$ROOT_DIR/output"
mkdir -p "$OUTPUT_DIR"

# 仓库路径（如果不存在，尝试克隆）
ATF_DIR="$ROOT_DIR/arm-trusted-firmware"
UBOOT_DIR="$ROOT_DIR/u-boot"
OWRT_DIR="$ROOT_DIR/immortalwrt"
CONFIG_DIR="$ROOT_DIR/888"

# 克隆函数（若需要）
clone_if_missing() {
    local dir=$1
    local repo_url=$2
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}目录 $dir 不存在，正在克隆 $repo_url ...${NC}"
        git clone --depth 1 "$repo_url" "$dir"
    fi
}

# 请根据实际仓库地址修改（这里以示例 URL 占位）
clone_if_missing "$ATF_DIR"   "https://github.com/mtk-openwrt/arm-trusted-firmware.git"
clone_if_missing "$UBOOT_DIR" "https://github.com/mtk-openwrt/u-boot.git"
clone_if_missing "$OWRT_DIR"  "https://github.com/immortalwrt/immortalwrt.git"

# ================= 1. 编译 ATF (生成 bl2.bin, bl31.bin) =================
echo -e "${GREEN}[1/5] 编译 ARM Trusted Firmware ...${NC}"
cd "$ATF_DIR"
# 根据 MT7981 配置进行编译（需根据实际 Makefile 调整）
make PLAT=mt7981 CROSS_COMPILE=aarch64-linux-gnu- bl2 bl31
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/bl2-emmc-ddr3.bin"
cp build/mt7981/release/bl31.bin "$OUTPUT_DIR/"

# ================= 2. 编译 U-Boot 并生成 FIP =================
echo -e "${GREEN}[2/5] 编译 U-Boot 并合成 FIP ...${NC}"
cd "$UBOOT_DIR"
# 设置默认配置（根据实际 defconfig 名称调整）
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 使用 ATF 的 fiptool 合成 FIP
cd "$ATF_DIR/tools/fiptool"
make
cd "$UBOOT_DIR"
"$ATF_DIR/tools/fiptool/fiptool" create \
    --soc-fw "$ATF_DIR/build/mt7981/release/bl31.bin" \
    --nt-fw "u-boot.bin" \
    "$OUTPUT_DIR/fip.bin"
# 重命名为需要的文件名
cp "$OUTPUT_DIR/fip.bin" "$OUTPUT_DIR/bl31-uboot-emmc-ddr3.fip"

# ================= 3. 准备 Factory 数据 =================
echo -e "${GREEN}[3/5] 准备 Factory 分区数据 ...${NC}"
FACTORY_FILE="$OUTPUT_DIR/factory_orig.bin"
if [ ! -f "$FACTORY_FILE" ]; then
    echo -e "${YELLOW}警告：未找到 factory_orig.bin，将生成 2MB 占位文件（可能缺少无线校准数据）。${NC}"
    dd if=/dev/zero of="$FACTORY_FILE" bs=1M count=2
fi

# ================= 4. 编译 OpenWrt (生成 sysupgrade.itb) =================
echo -e "${GREEN}[4/5] 编译 ImmortalWrt 内核与 rootfs ...${NC}"
cd "$OWRT_DIR"

# 应用设备配置文件
cp "$CONFIG_DIR/sl3000.config" .config
cp "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" target/linux/mediatek/dts/
cp "$CONFIG_DIR/mt7981_sl3000.mk" target/linux/mediatek/image/

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 扩展配置
make defconfig
make -j$(nproc) V=s

# 提取生成的 sysupgrade.itb
ITB_FILE=$(find bin/targets/mediatek/filogic -name "*-sysupgrade.itb" | head -1)
if [ -z "$ITB_FILE" ]; then
    echo -e "${RED}错误：未找到 sysupgrade.itb 文件！${NC}"
    exit 1
fi
cp "$ITB_FILE" "$OUTPUT_DIR/sysupgrade.itb"

# ================= 5. 合成 32MB 烧录包 =================
echo -e "${GREEN}[5/5] 合成最终 32MB 救砖固件 ...${NC}"
cd "$OUTPUT_DIR"

FINAL_BIN="sl3000-rescue-32mb.bin"

# 创建 32MB 全 0xFF 填充的空文件
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$FINAL_BIN"

# 按照分区布局写入各个部分
# 0M -> BL2 (256KB，实际写入大小由文件决定)
dd if=bl2-emmc-ddr3.bin of="$FINAL_BIN" conv=notrunc status=none

# 1M -> FIP
dd if=fip.bin of="$FINAL_BIN" bs=1M seek=1 conv=notrunc status=none

# 2M -> Factory (2MB)
dd if=factory_orig.bin of="$FINAL_BIN" bs=1M seek=2 conv=notrunc status=none

# 3M -> Kernel (sysupgrade.itb)
dd if=sysupgrade.itb of="$FINAL_BIN" bs=1M seek=3 conv=notrunc status=none

echo -e "${GREEN}✅ 构建完成！输出文件：${OUTPUT_DIR}/${FINAL_BIN}${NC}"
echo "文件大小：$(du -h "$FINAL_BIN" | cut -f1)"
