#!/bin/bash
set -euo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
MAIN_REPO="$WORKSPACE/main-repo"
OUTPUT_DIR="$WORKSPACE/output"

mkdir -p "$OUTPUT_DIR"/{atf,uboot}

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ---------- 编译 ATF ----------
cd "$MAIN_REPO/arm-trusted-firmware"
mkdir -p plat/mediatek/mt7981/drivers/dram
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
... (保留你原有的 DDR4 强制补丁) ...
EOF

# 1G eMMC BL2 + BL31
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=emmc DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-emmc.bin"
cp build/mt7981/release/bl31.bin "$OUTPUT_DIR/atf/bl31-1g-emmc.bin"

# 1G NOR BL2
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"

# RAM BL2 (救砖用)
make clean
make PLAT=mt7981 DEBUG=0 BOOT_DEVICE=ram DRAM_SIZE=1024 DRAM_USE_DDR4=1 BOARD_BGA=1 RAM_BOOT_UART_DL=1
cp build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-ram-1g.bin"

# ---------- 编译 fiptool ----------
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ---------- 编译 U-Boot eMMC 并打包 FIP ----------
cd "$MAIN_REPO/u-boot"
make clean
make mt7981_emmc_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)

"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-emmc.bin
cp fip-emmc.bin "$OUTPUT_DIR/uboot/"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-emmc.bin"

# ---------- 编译 U-Boot NOR 并打包 FIP ----------
make clean
make mt7981_spim_nor_rfb_defconfig
echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig
make -j$(nproc)

"$FIPTOOL" create --soc-fw "$OUTPUT_DIR/atf/bl31-1g-emmc.bin" --nt-fw u-boot.bin fip-nor.bin
cp fip-nor.bin "$OUTPUT_DIR/uboot/"
cp u-boot.bin "$OUTPUT_DIR/uboot/u-boot-nor.bin"

# ---------- 打包 mtk_uartboot ----------
cd "$MAIN_REPO/mtk_uartboot"
tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

echo "✅ 救砖全家桶构建完成"
ls -la "$OUTPUT_DIR"
