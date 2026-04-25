#!/bin/bash
set -euo pipefail

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
STAGING_IMAGE="$WORKSPACE/immortalwrt-build/staging_dir/image"

mkdir -p "$STAGING_IMAGE"

IMMORTALWRT_BUILD_DIR=$(cat "$WORKSPACE/build-dir.txt")
cd "$IMMORTALWRT_BUILD_DIR"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ARM Trusted Firmware (ATF) ==========
ATF_DIR="$SOURCE_DIR/arm-trusted-firmware"
cd "$ATF_DIR"

# 强制 DDR4
sed -i '/mt7981_use_ddr4 = /c\mt7981_use_ddr4 = 1;' plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c

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
        strings build/mt7981/release/bl2.bin | grep -qi "DDR4" || echo "⚠️ BL2 (${desc}) may not be DDR4"
    fi
    if [ -f build/mt7981/release/bl31.bin ]; then
        cp build/mt7981/release/bl31.bin "$STAGING_IMAGE/bl31-${desc}.bin"
    fi
}

build_atf "512m-emmc" 512 emmc ""
build_atf "1g-emmc" 1024 emmc ""
build_atf "1g-nor" 1024 nor ""
build_atf "ram-1g" 1024 ram "RAM_BOOT_UART_DL=1"

if [ ! -f "$STAGING_IMAGE/bl31-1g-emmc.bin" ]; then
    echo "❌ Missing bl31-1g-emmc.bin"
    exit 1
fi

# ========== 2. 编译 U-Boot 和生成 FIP ==========
FIPTOOL=$(find "$ATF_DIR/tools/fiptool" -name fiptool -type f | head -1)
if [ ! -x "$FIPTOOL" ]; then
    make -C "$ATF_DIR/tools/fiptool" CROSS_COMPILE=
    FIPTOOL="$ATF_DIR/tools/fiptool/fiptool"
fi

UBOOT_DIR="$SOURCE_DIR/u-boot"
cd "$UBOOT_DIR"

build_uboot_fip() {
    local desc="$1" defconfig="$2" bl31_name="$3"
    echo "=== Building U-Boot: $desc ==="
    make clean
    if [ ! -f "configs/${defconfig}" ]; then
        if [ -f "$WORKSPACE/main-repo/888/${defconfig}" ]; then
            cp "$WORKSPACE/main-repo/888/${defconfig}" configs/
        else
            echo "❌ defconfig $defconfig not found!"
            exit 1
        fi
    fi
    make "$defconfig"
    echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
    make olddefconfig
    make -j$(nproc)

    if [ -f fip.bin ] || [ -f u-boot.fip ]; then
        cp fip.bin "$OUTPUT_DIR/uboot/fip-${desc}.bin" 2>/dev/null || cp u-boot.fip "$OUTPUT_DIR/uboot/fip-${desc}.bin"
    else
        "$FIPTOOL" create \
            --soc-fw "$STAGING_IMAGE/${bl31_name}" \
            --nt-fw u-boot.bin \
            "$OUTPUT_DIR/uboot/fip-${desc}.bin"
    fi
    cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-${desc}.bin"
}

build_uboot_fip "emmc" "mt7981_emmc_rfb_defconfig" "bl31-1g-emmc.bin"
build_uboot_fip "nor" "mt7981_spim_nor_rfb_defconfig" "bl31-1g-nor.bin"

# ========== 3. 编译 ImmortalWrt 固件 ==========
echo "=== Building ImmortalWrt Firmware ==="
cd "$IMMORTALWRT_BUILD_DIR"

make VERSION_NUMBER="1.0.0" VERSION_CODE="r1" -j$(nproc) V=s 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Firmware build failed! Last 100 lines:"
    tail -100 build.log
    exit 1
fi

mkdir -p "$OUTPUT_DIR/firmware"
find bin/targets/ -type f \( -name "*.bin" -o -name "*sysupgrade*" \) -exec cp -v {} "$OUTPUT_DIR/firmware/" \;
cp build.log "$OUTPUT_DIR/firmware/"

# ========== 4. 打包 mtk_uartboot ==========
cd "$SOURCE_DIR/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
echo "✅ All tasks completed successfully"
