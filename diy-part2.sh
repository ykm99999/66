#!/bin/bash
set -euo pipefail

# ==========================================
# 核心指令：物理执行三准则 (救砖全量版 - 不构件升级包)
# ==========================================

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
OUTPUT_DIR="$WORKSPACE/output"
# 自动获取 part1 中保存的编译目录
IMMORTALWRT_BUILD=$(cat $WORKSPACE/build-dir.txt)
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"

mkdir -p "$OUTPUT_DIR/atf" "$OUTPUT_DIR/uboot" "$OUTPUT_DIR/firmware"

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ATF (原文照抄 DDR4 1G 补丁) ==========
echo "=== Building ATF (DDR4 1024M) ==="
cd $SOURCE_DIR/arm-trusted-firmware

# 注入 DDR4 强制初始化逻辑
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
cp -v build/mt7981/release/bl2.bin "$OUTPUT_DIR/atf/bl2-1g-nor.bin"
cp -v build/mt7981/release/bl31.bin "$STAGING_DIR_IMAGE/mt7981-nor-bl31.bin"

# ========== 2. 编译 U-Boot (原文照抄) ==========
echo "=== Building U-Boot (NOR) ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

cd $SOURCE_DIR/u-boot
make clean
make CROSS_COMPILE=aarch64-linux-gnu- mt7981_spim_nor_rfb_defconfig
# 延长等待时间防止 System Halt 无法干预
sed -i 's/CONFIG_BOOTDELAY=.*/CONFIG_BOOTDELAY=5/' .config
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
"$FIPTOOL" create --soc-fw "$STAGING_DIR_IMAGE/mt7981-nor-bl31.bin" --nt-fw u-boot.bin "$OUTPUT_DIR/uboot/fip-nor.bin"

# ========== 3. 构建最小化系统镜像 (仅生成必备组件) ==========
echo "=== Building ImmortalWrt Components ==="
cd "$IMMORTALWRT_BUILD"
# 只编译目标文件，不进行最后的打包（节省时间）
make -j$(nproc) target/compile || make -j1 V=s target/compile

# ========== 4. 物理缝合 32MB 救砖包 (像素级对齐) ==========
echo "=== 物理缝合 Spi-flash-32MB.bin ==="
cd "$OUTPUT_DIR/firmware"

# 寻找编译出的 ITB 镜像 (包含 Kernel + Rootfs)
# 注意：不使用 sysupgrade.bin，直接用原始 ITB 流
ITB_FILE=$(find "$IMMORTALWRT_BUILD/bin/targets/mediatek/filogic/" -name "*.itb" | head -n 1)

# 创建 32MB 纯净底图
dd if=/dev/zero bs=1k count=32768 | tr '\000' '\377' > Spi-flash-32MB.bin

# 注入 BL2 (Offset 0)
dd if="$OUTPUT_DIR/atf/bl2-1g-nor.bin" of=Spi-flash-32MB.bin conv=notrunc

# 注入 FIP (Offset 3.5MB / 3584k) - 修复 System Halt 关键点
dd if="$OUTPUT_DIR/uboot/fip-nor.bin" of=Spi-flash-32MB.bin bs=1k seek=3584 conv=notrunc

# 注入 System (Offset 4.0MB / 4096k)
if [ -n "$ITB_FILE" ]; then
    dd if="$ITB_FILE" of=Spi-flash-32MB.bin bs=1k seek=4096 conv=notrunc
    echo "✅ 32MB 救砖包物理缝合成功 (含 Rootfs)"
else
    echo "⚠️ 警告：未找到 ITB 文件，生成的是纯引导救砖包"
fi

# ========== 5. 整理输出产物 ==========
echo "=== Finalizing Artifacts ==="
cd "$OUTPUT_DIR"
# 压缩 uartboot 工具
cd "$SOURCE_DIR/mtk_uartboot" && tar -czf "$OUTPUT_DIR/mtk_uartboot.tar.gz" .

# 生成校验码
cd "$OUTPUT_DIR/firmware"
md5sum Spi-flash-32MB.bin > Spi-flash-32MB.bin.md5

echo "=== [Audit] 物理执行清单 ==="
ls -lh "$OUTPUT_DIR/firmware/Spi-flash-32MB.bin"
