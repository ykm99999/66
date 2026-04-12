#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
#  diy-part2.sh - 编译 ATF / U-Boot / 内核，并组装完整 32MB 镜像
# ------------------------------------------------------------

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD_DIR=$(cat "$WORKSPACE/build-dir.txt")

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

ATF_DIR="$SOURCE_DIR/arm-trusted-firmware"
UBOOT_DIR="$SOURCE_DIR/u-boot"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD_DIR/staging_dir/image"
mkdir -p "$STAGING_DIR_IMAGE" "$OUTPUT_DIR"/{atf,uboot,firmware}

# -------------------- 1. 编译 ATF (BL2 & BL31) --------------------
echo "=== 1. 编译 ATF (DDR4, NOR) ==="
cd "$ATF_DIR"
make clean
make CROSS_COMPILE=aarch64-linux-gnu- \
     PLAT=mt7981 \
     BOOT_DEVICE=nor \
     DDR_TYPE=ddr4 \
     DRAM_SIZE=1024 \
     NMBM=1 \
     BOARD=mt7981_bga \
     DEBUG=0 \
     LOG_LEVEL=20 \
     all

if [ ! -f build/mt7981/release/bl2.bin ] || [ ! -f build/mt7981/release/bl31.bin ]; then
    echo "❌ ATF 编译失败"
    exit 1
fi
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"
echo "✅ ATF 编译完成"

# -------------------- 2. 编译 fiptool --------------------
echo "=== 2. 编译 fiptool ==="
make fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"
if [ ! -f "$FIPTOOL" ]; then
    echo "❌ fiptool 未生成"
    exit 1
fi
chmod +x "$FIPTOOL"
mkdir -p "$UBOOT_DIR/tools"
cp -f "$FIPTOOL" "$UBOOT_DIR/tools/fiptool"
echo "✅ fiptool 准备完成"

# -------------------- 3. 编译 U-Boot --------------------
echo "=== 3. 编译 U-Boot ==="
cd "$UBOOT_DIR"

# 复制并适配 DTS
mkdir -p arch/arm/dts
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" arch/arm/dts/
sed -i '/&usb_phy {/a \    status = "disabled";' arch/arm/dts/mt7981b-sl3000-emmc.dts
sed -i '/&xhci {/a \    status = "disabled";' arch/arm/dts/mt7981b-sl3000-emmc.dts

# 修改 defconfig 中的默认设备树
DEFCONFIG="configs/mt7981_nor_emmc_rfb_defconfig"
if [ ! -f "$DEFCONFIG" ]; then
    echo "❌ U-Boot defconfig 不存在"
    exit 1
fi
cp "$DEFCONFIG" "$DEFCONFIG.bak"
sed -i 's/CONFIG_DEFAULT_DEVICE_TREE=".*"/CONFIG_DEFAULT_DEVICE_TREE="mt7981b-sl3000-emmc"/' "$DEFCONFIG"
sed -i 's/CONFIG_DEFAULT_FDT_FILE=".*"/CONFIG_DEFAULT_FDT_FILE="mt7981b-sl3000-emmc"/' "$DEFCONFIG"

make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_nor_emmc_rfb_defconfig
# 确保 FIP 支持及环境变量偏移正确
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
echo "CONFIG_ENV_IS_IN_SPI_FLASH=y" >> .config
echo "CONFIG_ENV_OFFSET=0x200000" >> .config
echo "CONFIG_ENV_SIZE=0x20000" >> .config
make olddefconfig

BL31_PATH="$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"
make CROSS_COMPILE=aarch64-linux-gnu- BL31="$BL31_PATH" -j$(nproc)

if [ ! -f u-boot.fip ]; then
    # 手动创建 FIP
    tools/fiptool create --soc-fw "$BL31_PATH" --nt-fw u-boot.bin u-boot.fip
fi
if [ ! -f u-boot.fip ]; then
    echo "❌ u-boot.fip 生成失败"
    exit 1
fi
cp u-boot.fip "$OUTPUT_DIR/uboot/fip-nor.bin"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"
echo "✅ U-Boot 编译完成"

# -------------------- 4. 编译 ImmortalWrt 内核 (initramfs) --------------------
echo "=== 4. 编译 ImmortalWrt 救援内核 ==="
cd "$IMMORTALWRT_BUILD_DIR"
rm -rf build_dir/host/libtool-*
make VERSION_NUMBER="1.0.0" VERSION_CODE="r1" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ 内核编译失败"
    tail -100 build.log
    exit 1
fi

RESCUE_KERNEL=$(find bin/targets/ -type f -name '*mt7981_sl3000_spi_rescue-initramfs-kernel.bin' | head -1)
if [ -z "$RESCUE_KERNEL" ]; then
    echo "❌ 未找到 initramfs 内核"
    exit 1
fi
cp -v "$RESCUE_KERNEL" "$OUTPUT_DIR/firmware/rescue-kernel.bin"
echo "✅ 救援内核编译完成"

# -------------------- 5. 组装完整 32MB SPI NOR 镜像 --------------------
echo "=== 5. 组装完整 32MB SPI NOR 镜像 ==="

# 准备空分区文件（若原备份存在则使用备份）
BACKUP_DIR="$SOURCE_DIR/original_backup"
mkdir -p "$BACKUP_DIR"

prepare_partition() {
    local name=$1
    local size=$2
    local out="$OUTPUT_DIR/atf/${name}.bin"
    if [ -f "$BACKUP_DIR/${name}.bin" ]; then
        cp "$BACKUP_DIR/${name}.bin" "$out"
    elif [ ! -f "$out" ]; then
        dd if=/dev/zero bs="$size" count=1 2>/dev/null | tr '\000' '\377' > "$out"
    fi
}

# 重命名 BL2 为统一名称
cp "$OUTPUT_DIR/atf/bl2-1g-nor.bin" "$OUTPUT_DIR/atf/BL2.bin"
prepare_partition "u-boot-env" $((0x20000))   # 128KB
prepare_partition "Factory"     $((0x200000)) # 2MB   WiFi 校准数据
prepare_partition "Product"     $((0x20000))  # 128KB
prepare_partition "Custom"      $((0x160000)) # 1.375MB

FULL_IMAGE="$OUTPUT_DIR/firmware/SL3000-full-spi-nor-32mb.bin"

# 创建 32MB 全 0xFF 的空白镜像
dd if=/dev/zero bs=1M count=32 2>/dev/null | tr '\000' '\377' > "$FULL_IMAGE"

# 按照 MT7981 固定分区布局写入 (与 DTS 完全一致)
# 布局：
# 0x000000 - 0x03FFFF : BL2         (256KB)
# 0x040000 - 0x1FFFFF : FIP         (1.75MB)
# 0x200000 - 0x21FFFF : u-boot-env  (128KB)
# 0x220000 - 0xE1FFFF : kernel      (12MB)
# 0xE20000 - 0x1FFFFFF : rootfs     (约 18MB，本救援包暂不写入)
# 后续保留分区按原厂偏移写入

dd if="$OUTPUT_DIR/atf/BL2.bin" of="$FULL_IMAGE" bs=1 conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$FULL_IMAGE" bs=1 seek=$((0x40000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/u-boot-env.bin" of="$FULL_IMAGE" bs=1 seek=$((0x200000)) conv=notrunc
dd if="$OUTPUT_DIR/firmware/rescue-kernel.bin" of="$FULL_IMAGE" bs=1 seek=$((0x220000)) conv=notrunc
# 写入原厂其他分区（保留偏移）
dd if="$OUTPUT_DIR/atf/Factory.bin" of="$FULL_IMAGE" bs=1 seek=$((0x180000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/Product.bin" of="$FULL_IMAGE" bs=1 seek=$((0x1e80000)) conv=notrunc
dd if="$OUTPUT_DIR/atf/Custom.bin" of="$FULL_IMAGE" bs=1 seek=$((0x1ea0000)) conv=notrunc

echo "✅ 完整 32MB SPI NOR 镜像已生成：$FULL_IMAGE"
ls -lh "$FULL_IMAGE"

# -------------------- 6. 打包 mtk_uartboot 工具 --------------------
if [ -d "$SOURCE_DIR/mtk_uartboot" ]; then
    cd "$SOURCE_DIR/mtk_uartboot"
    tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
    echo "✅ mtk_uartboot 打包完成"
fi

echo "=== 所有构建任务完成 ==="
ls -la "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"
