#!/bin/bash
set -e  # 遇到错误立即退出

# 定义路径（相对于 main-repo 目录）
SOURCE_DIR="../source-repo"
CONFIG_DIR="888"          # 888 目录就在 main-repo 下
OUTPUT_DIR="../output"    # 输出目录位于 main-repo 的上一级

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware

# ---------- 1. 编译 ATF ----------
echo "=== Building ATF 512M ==="
cd $SOURCE_DIR/arm-trusted-firmware
make clean
make PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512
cp build/mt7981/release/bl2/bl2.elf $OUTPUT_DIR/atf/bl2-512m.elf 2>/dev/null || true
[ -f build/mt7981/release/bl2.bin ] && cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-512m.bin

make clean
make PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024
cp build/mt7981/release/bl2/bl2.elf $OUTPUT_DIR/atf/bl2-1g.elf 2>/dev/null || true
[ -f build/mt7981/release/bl2.bin ] && cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g.bin

# ---------- 2. 编译 U-Boot ----------
echo "=== Building U-Boot ==="
cd $SOURCE_DIR/u-boot
make clean
if [ -f configs/mt7981_sl3000_emmc_defconfig ]; then
    make mt7981_sl3000_emmc_defconfig
elif [ -f configs/mt7981_emmc_defconfig ]; then
    make mt7981_emmc_defconfig
else
    make defconfig
fi
make -j$(nproc)
[ -f fip.bin ] && cp fip.bin $OUTPUT_DIR/uboot/fip.bin
[ -f u-boot.bin ] && cp u-boot.bin $OUTPUT_DIR/uboot/u-boot.bin

# ---------- 3. 准备 ImmortalWrt 源码 ----------
cd ../..
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 复制三件套文件（从 main-repo/888/ 复制）
cp ../main-repo/$CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts target/linux/mediatek/dts/
cp ../main-repo/$CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts target/linux/mediatek/dts/
cp ../main-repo/$CONFIG_DIR/mt7981.mk target/linux/mediatek/image/
cp ../main-repo/$CONFIG_DIR/sl3000-1g.config .config   # 根据需要选择配置文件

# ---------- 4. 编译 ImmortalWrt ----------
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make -j$(nproc) V=s 2>&1 | tee build.log

# 收集固件
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp {} $OUTPUT_DIR/firmware/ \;
cp build.log $OUTPUT_DIR/firmware/

# ---------- 5. 打包 mtk_uartboot ----------
cd $SOURCE_DIR/mtk_uartboot
tar -czf $OUTPUT_DIR/mtk_uartboot.tar.gz .

echo "✅ 构建完成，产物位于: $OUTPUT_DIR"
