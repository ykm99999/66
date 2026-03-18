#!/bin/bash
set -e

# ========== 全文件检测 ==========
echo "=== Checking all required source files ==="

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"

MISSING_FILES=()

# 定义需要检查的文件列表（相对路径）
FILES_TO_CHECK=(
    # ATF
    "arm-trusted-firmware/plat/mediatek/mt7981/platform.mk"
    "arm-trusted-firmware/bl2/bl2_main.c"
    "arm-trusted-firmware/fdts/mt7981.dts"
    "arm-trusted-firmware/bl2/bl2.ld.S"
    "arm-trusted-firmware/tools/fiptool/fiptool.c"
    # U-Boot
    "u-boot/configs/mt7981_emmc_rfb_defconfig"
    "u-boot/configs/mt7981_spim_nor_rfb_defconfig"
    "u-boot/arch/arm/dts/mt7981.dtsi"
    "u-boot/board/mediatek/mt7981/Kconfig"
    # ImmortalWrt（目录和关键文件）
    "immortalwrt/target/linux/mediatek"
    "immortalwrt/feeds.conf.default"
    "immortalwrt/scripts/feeds"
    # mtk_uartboot
    "mtk_uartboot/Cargo.toml"
    "mtk_uartboot/src/main.rs"
    # bl-mt798x（可选，只检查目录存在）
    "bl-mt798x"
)

for FILE in "${FILES_TO_CHECK[@]}"; do
    if [ ! -e "$SOURCE_DIR/$FILE" ]; then
        MISSING_FILES+=("$SOURCE_DIR/$FILE")
    fi
done

# 检查配置目录中的三件套文件
CONFIG_FILES=(
    "mt7981.mk"
    "sl3000.config"
    "mt7981-sl-3000-emmc-1g.dts"
    "mt7981-sl-3000-emmc-512m.dts"
)

for FILE in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$CONFIG_DIR/$FILE" ]; then
        MISSING_FILES+=("$CONFIG_DIR/$FILE")
    fi
done

if [ ${#MISSING_FILES[@]} -ne 0 ]; then
    echo "❌ Missing required files:"
    for MISSING in "${MISSING_FILES[@]}"; do
        echo "   - $MISSING"
    done
    exit 1
else
    echo "✅ All required files are present."
fi

# ========== 创建输出目录 ==========
mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ATF ==========
echo "=== Building ATF 512M (EMMC) ==="
cd $SOURCE_DIR/arm-trusted-firmware
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 512M emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 512M emmc"

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 1G emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 1G emmc"

echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

# 复制 bl31.bin（路径已修正）
cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin 2>/dev/null || echo "No bl31.bin for emmc"
cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin 2>/dev/null || echo "No bl31.bin for nor"

# 编译 ATF 自带的 fiptool
echo "=== Compiling fiptool from ATF ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ========== 2. 编译 U-Boot (eMMC版) 并生成 FIP ==========
echo "=== Building U-Boot (eMMC) ==="
cd $SOURCE_DIR/u-boot
make clean
if [ -f configs/mt7981_emmc_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
else
    echo "❌ mt7981_emmc_rfb_defconfig not found!"
    exit 1
fi

# 确保 FIP 支持已启用
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig

make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 检查并生成 FIP
if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    echo "⚠️ fip.bin not generated, creating manually..."
    if [ -f "$FIPTOOL" ]; then
        "$FIPTOOL" create \
            --soc-fw $STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin \
            --nt-fw u-boot.bin \
            u-boot.fip
        cp u-boot.fip $OUTPUT_DIR/uboot/fip-emmc.bin
    else
        echo "❌ fiptool not found, cannot create FIP"
        exit 1
    fi
else
    cp fip.bin $OUTPUT_DIR/uboot/fip-emmc.bin 2>/dev/null || cp u-boot.fip $OUTPUT_DIR/uboot/fip-emmc.bin 2>/dev/null
fi
cp u-boot.bin $OUTPUT_DIR/uboot/u-boot-emmc.bin

# ========== 3. 编译 ImmortalWrt ==========
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 更新 feeds
echo "=== Updating feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

# ========== 【修复】临时移除有依赖问题的包 ==========
echo "=== Temporarily removing problematic package ==="
rm -f package/feeds/packages/onionshare-cli/Makefile

# 复制三件套文件
echo "=== Copying device-specific files ==="
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts target/linux/mediatek/dts/ || echo "❌ 1G DTS copy failed"
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts target/linux/mediatek/dts/ || echo "❌ 512M DTS copy failed"
cp -v $CONFIG_DIR/mt7981.mk target/linux/mediatek/image/ || { echo "❌ mt7981.mk copy failed"; exit 1; }
cp -v $CONFIG_DIR/sl3000.config .config || { echo "❌ sl3000.config copy failed"; exit 1; }

# 强制启用您的设备
echo "=== Enabling devices ==="
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-1g=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-512m=y" >> .config

# 重新生成配置
make defconfig
# 确保设备选项仍然启用（defconfig 可能会重置，但目标平台已选，通常会自动出现，保险起见再次添加）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-1g=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-512m=y" >> .config
make olddefconfig

# 列出启用的设备
echo "=== Enabled mediatek/filogic devices ==="
make info | grep -A 30 "Target: mediatek/filogic" | grep "sl_3000" || echo "⚠️ Devices not enabled!"

# 编译
echo "=== Building ImmortalWrt ==="
make -j$(nproc) V=s 2>&1 | tee build.log

# 列出并收集固件
echo "=== Listing generated images ==="
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -ls

echo "=== Collecting firmware ==="
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} $OUTPUT_DIR/firmware/ \;
cp build.log $OUTPUT_DIR/firmware/

# ========== 4. 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf $OUTPUT_DIR/mtk_uartboot.tar.gz .

# ========== 最终输出 ==========
echo "✅ Build complete. Output directory contents:"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
