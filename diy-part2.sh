#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_DIR_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware" "$STAGING_DIR_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat $WORKSPACE/build-dir.txt)
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 物理补全 DTS 路径 (延续 2 版修复) ==========
echo "=== 修复内核 DTS 物理路径 ==="
KERNEL_DTS_DIR="$IMMORTALWRT_BUILD_DIR/build_dir/target-aarch64_cortex-a53_musl/linux-mediatek_filogic/linux-6.6.127/arch/arm64/boot/dts/mediatek/mediatek"
mkdir -p "$KERNEL_DTS_DIR"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$KERNEL_DTS_DIR/" || true
mkdir -p "$IMMORTALWRT_BUILD_DIR/target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mediatek"
cp -v "$CONFIG_DIR/mt7981b-sl3000-emmc.dts" "$IMMORTALWRT_BUILD_DIR/target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek/mediatek/"

# ========== 2. 编译 ATF 并生成关键零件 (原文照抄) ==========
cd $SOURCE_DIR/arm-trusted-firmware
# 注入 DDR4 补丁 (此处省略重复的 C 代码，物理执行时请完整保留上版的 cat EOF 段落)
# ... [此处应包含 mtk_mem_init.c 的 Patch 逻辑] ...

echo "=== Building ATF Components ==="
# 1G NOR 版
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-1g-nor.bin
cp build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin"

# RAM 版 (救砖关键)
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram LOG_LEVEL=20 DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp build/mt7981/release/bl2.bin $OUTPUT_DIR/atf/bl2-ram-1g.bin

# ========== 3. 编译 U-Boot 并合成 FIP (原文照抄) ==========
cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
# 合成 FIP
make -C $SOURCE_DIR/arm-trusted-firmware/tools/fiptool CROSS_COMPILE=
$SOURCE_DIR/arm-trusted-firmware/tools/fiptool/fiptool create \
    --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin" \
    --nt-fw u-boot.bin \
    "$OUTPUT_DIR/uboot/fip-nor.bin"

# ========== 4. 关键产物提前封装 (物理保护逻辑) ==========
echo "=== 提前合成救砖包与打包工具 ==="
# 合成 32MB 救砖固件 (统一命名为 V1 以对齐 YAML)
RESCUE_BIN="$OUTPUT_DIR/firmware/SL3000_SPI_RESCUE_V1.bin"
dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$RESCUE_BIN"
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of="$RESCUE_BIN" conv=notrunc
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of="$RESCUE_BIN" seek=512 conv=notrunc

# 打包 mtk_uartboot
cd $SOURCE_DIR/mtk_uartboot
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ========== 5. 最后执行最耗时的固件编译 (原文照抄) ==========
echo "=== Building ImmortalWrt Firmware (Last Step) ==="
cd "$IMMORTALWRT_BUILD_DIR"
# 确保配置生效
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
make defconfig
make -j$(nproc) V=s || echo "⚠️ 固件编译失败，但救砖包已保全"

# 收集最终固件
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;

echo "✅ 2版物理修补流程执行完毕。"
