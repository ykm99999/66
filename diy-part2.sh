#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ATF (使用动态查找) ==========
echo "=== Building ATF 512M ==="
cd $SOURCE_DIR/arm-trusted-firmware
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512

# 动态查找 bl2 文件
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m.bin \; 2>/dev/null || true
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-512m.elf \; 2>/dev/null || true

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024

find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g.bin \; 2>/dev/null || true
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g.elf \; 2>/dev/null || true

# ========== 2. 编译 U-Boot ==========
echo "=== Building U-Boot ==="
cd $SOURCE_DIR/u-boot
make clean

# 优先使用 mt7981_emmc_rfb_defconfig，如果没有则尝试其他 emmc 配置
if [ -f configs/mt7981_emmc_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
elif [ -f configs/mt7981_emmc_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_defconfig
else
    # 尝试找到任何包含 emmc 的 mt7981 配置
    EMMC_CONFIG=$(ls configs/mt7981*emmc*_defconfig 2>/dev/null | head -1)
    if [ -n "$EMMC_CONFIG" ]; then
        CONFIG_NAME=$(basename "$EMMC_CONFIG" .h)
        make CROSS_COMPILE=aarch64-linux-gnu- "$CONFIG_NAME"
    else
        echo "❌ No suitable emmc config found!"
        exit 1
    fi
fi

make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
[ -f fip.bin ] && cp fip.bin $OUTPUT_DIR/uboot/fip.bin
[ -f u-boot.bin ] && cp u-boot.bin $OUTPUT_DIR/uboot/u-boot.bin

# ========== 3. 编译 ImmortalWrt ==========
cd $WORKSPACE
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

cp $CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts target/linux/mediatek/dts/
cp $CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts target/linux/mediatek/dts/
cp $CONFIG_DIR/mt7981.mk target/linux/mediatek/image/
cp $CONFIG_DIR/sl3000-1g.config .config   # 可改为 512m 版本

./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make -j$(nproc) V=s 2>&1 | tee build.log

find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp {} $OUTPUT_DIR/firmware/ \;
cp build.log $OUTPUT_DIR/firmware/

# ========== 4. 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf $OUTPUT_DIR/mtk_uartboot.tar.gz .

echo "✅ 构建完成，产物位于: $OUTPUT_DIR"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
