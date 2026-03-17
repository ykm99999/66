#!/bin/bash
set -e  # 遇到错误立即退出

# 定义源码路径（假设源码在仓库的 source-repo 子目录，您可以根据实际调整）
SOURCE_DIR="source-repo"
CONFIG_DIR="config-repo/888"  # 如果您的三件套在 main 分支的 888 目录

# 创建输出目录
mkdir -p output/atf output/uboot output/firmware

# 1. 编译 ATF (512M 和 1G)
echo "=== Building ATF 512M ==="
cd $SOURCE_DIR/arm-trusted-firmware
make clean
make PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512
cp build/mt7981/release/bl2/bl2.elf ../../output/atf/bl2-512m.elf 2>/dev/null || true
[ -f build/mt7981/release/bl2.bin ] && cp build/mt7981/release/bl2.bin ../../output/atf/bl2-512m.bin

make clean
make PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024
cp build/mt7981/release/bl2/bl2.elf ../../output/atf/bl2-1g.elf 2>/dev/null || true
[ -f build/mt7981/release/bl2.bin ] && cp build/mt7981/release/bl2.bin ../../output/atf/bl2-1g.bin

# 2. 编译 U-Boot
echo "=== Building U-Boot ==="
cd ../../$SOURCE_DIR/u-boot
make clean
# 优先使用 SL3000 专用配置
if [ -f configs/mt7981_sl3000_emmc_defconfig ]; then
    make mt7981_sl3000_emmc_defconfig
elif [ -f configs/mt7981_emmc_defconfig ]; then
    make mt7981_emmc_defconfig
else
    make defconfig
fi
make -j$(nproc)
[ -f fip.bin ] && cp fip.bin ../../output/uboot/fip.bin
[ -f u-boot.bin ] && cp u-boot.bin ../../output/uboot/u-boot.bin

# 3. 准备 ImmortalWrt 源码（复制一份，避免污染）
cd ../..
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 复制您的三件套文件（假设它们位于仓库根目录的 888/ 下，需要从 config-repo 复制）
cp ../$CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts target/linux/mediatek/dts/
cp ../$CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts target/linux/mediatek/dts/
cp ../$CONFIG_DIR/mt7981.mk target/linux/mediatek/image/
cp ../$CONFIG_DIR/sl3000-1g.config .config   # 假设您有 1G 的配置文件
# 您也可以根据需求选择编译 512M 版本，这里以 1G 为例

# 4. 编译 ImmortalWrt
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make -j$(nproc) V=s 2>&1 | tee build.log

# 5. 收集固件
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp {} ../output/firmware/ \;
cp build.log ../output/firmware/

# 6. 打包 mtk_uartboot（如果需要）
cd ../$SOURCE_DIR/mtk_uartboot
tar -czf ../../output/mtk_uartboot.tar.gz .

echo "✅ 所有构建完成，产物在 output/ 目录"
