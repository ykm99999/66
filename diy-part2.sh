#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/main-repo"
OUTPUT_DIR="$SOURCE_DIR/output"
STAGING_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat "$WORKSPACE/build-dir.txt")
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ATF ==========
ATF_DIR="$SOURCE_DIR/arm-trusted-firmware"
cd "$ATF_DIR"

build_atf() {
    local desc="$1" dram="$2" bootdev="$3" rammode="$4"
    echo "=== Building ATF: $desc ==="
    make clean
    make CROSS_COMPILE=aarch64-linux-gnu- \
        PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 \
        BOOT_DEVICE="$bootdev" LOG_LEVEL=20 DRAM_SIZE="$dram" \
        DDR_TYPE=ddr4 DRAM_USE_DDR4=1 BOARD_BGA=1 \
        $rammode -j$(nproc)

    if [ -f build/mt7981/release/bl2.bin ]; then
        cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-${desc}.bin"
    fi
    if [ -f build/mt7981/release/bl31.bin ]; then
        cp build/mt7981/release/bl31.bin "$STAGING_IMAGE/bl31-${desc}.bin"
    fi
}

build_atf "1g-nor" 1024 nor ""
build_atf "1g-emmc" 1024 emmc ""
build_atf "ram-1g" 1024 ram "RAM_BOOT_UART_DL=1"

if [ ! -f "$STAGING_IMAGE/bl31-1g-nor.bin" ]; then
    echo "❌ Missing bl31 for NOR"
    exit 1
fi

# ========== 2. 编译 U-Boot 和 FIP ==========
cd "$ATF_DIR"
make fiptool CROSS_COMPILE=
FIPTOOL="$ATF_DIR/tools/fiptool/fiptool"

UBOOT_DIR="$SOURCE_DIR/u-boot"
cd "$UBOOT_DIR"

build_uboot_fip() {
    local desc="$1" defconfig="$2" bl31_bin="$3"
    echo "=== Building U-Boot: $desc ==="
    make clean
    if [ ! -f "configs/${defconfig}" ]; then
        echo "❌ defconfig $defconfig not found!"
        exit 1
    fi
    make "$defconfig"
    echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
    make olddefconfig
    make -j$(nproc)

    if [ -f fip.bin ]; then
        cp fip.bin "$OUTPUT_DIR/uboot/fip-${desc}.bin"
    elif [ -f u-boot.fip ]; then
        cp u-boot.fip "$OUTPUT_DIR/uboot/fip-${desc}.bin"
    else
        "$FIPTOOL" create \
            --soc-fw "$STAGING_IMAGE/${bl31_bin}" \
            --nt-fw u-boot.bin \
            "$OUTPUT_DIR/uboot/fip-${desc}.bin"
    fi
    cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-${desc}.bin"
}

build_uboot_fip "nor" "mt7981_spim_nor_rfb_defconfig" "bl31-1g-nor.bin"

# ========== 3. 编译 ImmortalWrt（自动回答所有内核配置询问）==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"

# 关键：使用 yes "" 自动接受所有内核新选项的默认值
yes "" | make VERSION_NUMBER="1.0.0" VERSION_CODE="r1" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f \( -name "*.bin" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
cp build.log "$OUTPUT_DIR/firmware/"

# ========== 4. 打包 mtk_uartboot ==========
cd "$SOURCE_DIR/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# ========== 5. 合成 32MB 救砖镜像 ==========
echo "=== Assembling 32MB rescue image ==="
BL2_NOR="$OUTPUT_DIR/atf/bl2-1g-nor.bin"
FIP_NOR="$OUTPUT_DIR/uboot/fip-nor.bin"
if [ ! -f "$BL2_NOR" ] || [ ! -f "$FIP_NOR" ]; then
    echo "❌ Missing BL2 or FIP for NOR"
    exit 1
fi

SYS_FILE=$(find "$OUTPUT_DIR/firmware" -name "*sysupgrade*" -type f | head -1)
if [ -z "$SYS_FILE" ]; then
    echo "❌ No sysupgrade file found"
    exit 1
fi

TMP_SYS="$(mktemp -d)"
tar -xf "$SYS_FILE" -C "$TMP_SYS"
KERNEL_FIT="$TMP_SYS/kernel"
ROOTFS_SQ="$TMP_SYS/root"
if [ ! -f "$KERNEL_FIT" ] || [ ! -f "$ROOTFS_SQ" ]; then
    echo "❌ Missing kernel or root in sysupgrade"
    rm -rf "$TMP_SYS"
    exit 1
fi

dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$OUTPUT_DIR/rescue/sl3000-full-${GITHUB_RUN_ID:-0}.bin"
dd if="$BL2_NOR" of="$OUTPUT_DIR/rescue/sl3000-full-${GITHUB_RUN_ID:-0}.bin" bs=1 conv=notrunc status=none
dd if="$FIP_NOR" of="$OUTPUT_DIR/rescue/sl3000-full-${GITHUB_RUN_ID:-0}.bin" bs=1 seek=$((0x380000)) conv=notrunc status=none

FACTORY_BIN="$SOURCE_DIR/888/factory.bin"
if [ -f "$FACTORY_BIN" ]; then
    echo "✅ 找到 factory.bin，恢复校准数据"
    dd if="$FACTORY_BIN" of="$OUTPUT_DIR/rescue/sl3000-full-${GITHUB_RUN_ID:-0}.bin" bs=1 seek=$((0x180000)) conv=notrunc status=none
else
    echo "⚠️ 缺少 factory.bin，MAC/WiFi 可能无效"
fi

FIRMWARE_PART="$OUTPUT_DIR/rescue/firmware_part.bin"
cat "$KERNEL_FIT" "$ROOTFS_SQ" > "$FIRMWARE_PART"
FIRMSIZE=$(stat -c%s "$FIRMWARE_PART")
if [ "$FIRMSIZE" -gt 26214400 ]; then
    echo "❌ firmware 分区超限"
    rm -rf "$TMP_SYS" "$FIRMWARE_PART"
    exit 1
fi
dd if=/dev/zero bs=1 count=$((26214400 - FIRMSIZE)) >> "$FIRMWARE_PART"
dd if="$FIRMWARE_PART" of="$OUTPUT_DIR/rescue/sl3000-full-${GITHUB_RUN_ID:-0}.bin" bs=1 seek=$((0x580000)) conv=notrunc status=none

rm -rf "$TMP_SYS" "$FIRMWARE_PART"

echo "✅ Rescue image: $OUTPUT_DIR/rescue/sl3000-full-*.bin"
