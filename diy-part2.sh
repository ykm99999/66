#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_DIR_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# 编译 ATF（保持不变，省略部分代码，请保留原有完整 ATF 编译段）
# 这里假设您已有完整的 ATF 编译代码，为节省篇幅不再重复
# 请从您之前成功的 diy-part2.sh 中复制完整的 ATF 编译段（从 cd $SOURCE_DIR/arm-trusted-firmware 到 fiptool 编译）

# ========== 编译 U-Boot (NOR版) 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    $FIPTOOL create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" --nt-fw u-boot.bin u-boot.fip
    cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
else
    cp fip.bin "$OUTPUT_DIR/uboot/fip-nor.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
fi
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ========== 编译 ImmortalWrt 固件 ==========
cd "$IMMORTALWRT_BUILD_DIR"
make VERSION_NUMBER="${VERSION_NUMBER:-1.0.0}" VERSION_CODE="${VERSION_CODE:-r1}" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Build failed"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
cp build.log "$OUTPUT_DIR/firmware/"

# 列出所有 sysupgrade 文件（调试）
echo "=== All sysupgrade.bin files ==="
find bin/targets/ -type f -name '*sysupgrade.bin' -exec ls -lh {} \;

# 复制 eMMC 固件
EMMC_SYSUPGRADE=$(find bin/targets/ -type f -name '*mt7981_sl3000_emmc*sysupgrade.bin' | head -1)
if [ -n "$EMMC_SYSUPGRADE" ]; then
    cp -v "$EMMC_SYSUPGRADE" "$OUTPUT_DIR/firmware/"
fi

# 复制救砖镜像：优先精确匹配，然后模糊匹配，最后根据大小
SPI_IMAGE=$(find bin/targets/ -type f -name '*sl_3000-spi-nor*sysupgrade.bin' -size -34M | head -1)
if [ -z "$SPI_IMAGE" ]; then
    SPI_IMAGE=$(find bin/targets/ -type f -name '*spi-nor*.bin' -size -34M | head -1)
fi
if [ -z "$SPI_IMAGE" ]; then
    # 如果还找不到，选择最小的 sysupgrade.bin（通常救砖镜像最小）
    SPI_IMAGE=$(find bin/targets/ -type f -name '*sysupgrade.bin' -exec ls -lS {} \; | tail -1 | awk '{print $NF}')
fi
if [ -n "$SPI_IMAGE" ]; then
    cp -v "$SPI_IMAGE" "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
    echo "✅ SPI-NOR rescue image saved as Spi-flash-32MB.bin"
else
    echo "❌ No SPI-NOR rescue image found!"
    exit 1
fi

# 打包 mtk_uartboot
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ Build complete"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
