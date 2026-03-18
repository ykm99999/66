#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"

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

# 【修复1】修正 bl31.bin 路径
cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin 2>/dev/null || echo "No bl31.bin for emmc"
cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin 2>/dev/null || echo "No bl31.bin for nor"

# 【修复2】编译 ATF 自带的 fiptool
echo "=== Compiling fiptool from ATF ==="
make -C tools/fiptool CROSS_COMPILE=  # 主机工具不需要交叉编译
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

# 检查是否生成 fip.bin，若没有则手动创建
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

# 复制三件套文件
echo "=== 复制三件套文件 ==="
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts target/linux/mediatek/dts/ || echo "❌ 1G DTS copy failed"
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts target/linux/mediatek/dts/ || echo "❌ 512M DTS copy failed"
cp -v $CONFIG_DIR/mt7981.mk target/linux/mediatek/image/ || { echo "❌ mt7981.mk copy failed"; exit 1; }
cp -v $CONFIG_DIR/sl3000.config .config || { echo "❌ sl3000.config copy failed"; exit 1; }

# 验证复制结果
echo "=== target/linux/mediatek/dts/ 内容 ==="
ls -la target/linux/mediatek/dts/mt7981*.dts
echo "=== target/linux/mediatek/image/ 内容 ==="
ls -la target/linux/mediatek/image/mt7981.mk

# 强制启用您的设备
echo "=== 强制启用设备 ==="
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-1g=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-512m=y" >> .config

# 更新 feeds
echo "=== 更新 feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

# 重新生成配置
make olddefconfig

# 列出启用的设备
echo "=== 当前启用的 mediatek/filogic 设备 ==="
make info | grep -A 30 "Target: mediatek/filogic" | grep "sl_3000" || echo "⚠️ 您的设备未在启用列表中！"

# 编译
echo "=== 开始编译 ImmortalWrt ==="
make -j$(nproc) V=s 2>&1 | tee build.log

# 列出并收集固件
echo "=== 列出 bin/targets/ 下所有镜像 ==="
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -ls

echo "=== 收集固件到 output/firmware ==="
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} $OUTPUT_DIR/firmware/ \;
cp build.log $OUTPUT_DIR/firmware/

# ========== 4. 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf $OUTPUT_DIR/mtk_uartboot.tar.gz .

# ========== 最终输出 ==========
echo "✅ 构建完成，输出目录内容:"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
