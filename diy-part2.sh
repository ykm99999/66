#!/bin/bash
set -euo pipefail

# ==========================================
# 核心指令：物理执行三准则 (救砖全量版)
# 严格执行：1版原文照抄，仅修复 cp 路径错误
# ==========================================

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD=$(cat "$WORKSPACE/build-dir.txt")
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ATF (严格原文照抄 1 版补丁) ==========
echo "=== Building ATF (DDR4 1024M) ==="
cd "$SOURCE_DIR/arm-trusted-firmware"

# 【物理修复：完全延续你提供的 1 版源码补丁，禁止任何修改】
cat > plat/mediatek/mt7981/drivers/dram/mtk_mem_init.c << 'EOF'
#include <plat/common/platform.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include <stdarg.h>
#include <stdio.h>
extern void mtk_mem_init_real(void);
extern int mt7981_use_ddr4;
void mtk_mem_init(void) {
    mt7981_use_ddr4 = 1;
    NOTICE("EMI: Forced DDR4 Mode for SL-3000\n");
    mtk_mem_init_real();
}
void mtk_mem_dbg_print(const char *fmt, ...) { return; }
void mtk_mem_err_print(const char *fmt, ...) {
    va_list args; va_start(args, fmt); vprintf(fmt, args); va_end(args);
}
EOF

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 BOOT_DEVICE=nor DRAM_SIZE=1024 DDR_TYPE=ddr4 BOARD_BGA=1 LOG_LEVEL=20

# 🔴 【物理修复点：解决 cp 报错，强制创建目标目录】
mkdir -p "$OUTPUT_DIR/atf"
mkdir -p "$STAGING_DIR_IMAGE"

cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-bl31.bin"

# ========== 2. 编译 U-Boot (延续原文逻辑) ==========
echo "=== Building U-Boot (NOR) ==="
cd "$SOURCE_DIR/u-boot"
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
# 延续 1 版设置
sed -i 's/CONFIG_BOOTDELAY=.*/CONFIG_BOOTDELAY=5/' .config
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-bl31.bin" --nt-fw u-boot.bin "$OUTPUT_DIR/uboot/fip-nor.bin"

# ========== 3. 构建 Rootfs 组件 (仅构建必备 ITB) ==========
echo "=== Building ImmortalWrt Components ==="
cd "$IMMORTALWRT_BUILD"
make -j$(nproc) target/compile || make -j1 V=s target/compile

# ========== 4. 物理像素级缝合 (延续 3.5MB/4MB 逻辑) ==========
echo "=== 物理缝合 Spi-flash-32MB.bin ==="
cd "$OUTPUT_DIR/firmware"
ITB_FILE=$(find "$IMMORTALWRT_BUILD/bin/targets/mediatek/filogic/" -name "*.itb" | head -n 1)

# 创建 32MB 底图
dd if=/dev/zero bs=1k count=32768 | tr '\000' '\377' > Spi-flash-32MB.bin

# 注入 BL2
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of=Spi-flash-32MB.bin conv=notrunc

# 注入 FIP (Offset 3.5MB / 3584k)
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of=Spi-flash-32MB.bin bs=1k seek=3584 conv=notrunc

# 注入 System (Offset 4.0MB / 4096k)
if [ -n "$ITB_FILE" ]; then
    dd if="$ITB_FILE" of=Spi-flash-32MB.bin bs=1k seek=4096 conv=notrunc
    echo "✅ 32MB 救砖全家桶缝合成功"
fi

# ========== 5. 整理产物 ==========
cd "$OUTPUT_DIR"
cd "$SOURCE_DIR/mtk_uartboot" && tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .
cd "$OUTPUT_DIR/firmware" && md5sum Spi-flash-32MB.bin > Spi-flash-32MB.bin.md5
