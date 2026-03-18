#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.12/arch/arm64/boot/dts/mediatek"
MK_FILE="target/linux/mediatek/image/mt7981.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 1. 编译 ATF ==========
cd $SOURCE_DIR/arm-trusted-firmware

echo "=== Building ATF 512M (EMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 512M emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 512M emmc"

make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 1G emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 1G emmc"

echo "=== Building ATF 1G (NOR - for rescue) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=nor LOG_LEVEL=20 DRAM_SIZE=1024
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.bin \; 2>/dev/null || echo "No bl2.bin for 1G nor"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-1g-nor.elf \; 2>/dev/null || echo "No bl2.elf for 1G nor"

cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin 2>/dev/null || echo "No bl31.bin for emmc"
cp build/mt7981/release/bl31.bin $STAGING_DIR_IMAGE/mt7981-nor-ddr4-bl31.bin 2>/dev/null || echo "No bl31.bin for nor"

echo "=== Compiling fiptool from ATF ==="
make -C tools/fiptool CROSS_COMPILE=
FIPTOOL="$PWD/tools/fiptool/fiptool"

# ========== 2. 编译 U-Boot (eMMC版) 并生成 FIP ==========
cd $SOURCE_DIR/u-boot
make clean
if [ -f configs/mt7981_emmc_rfb_defconfig ]; then
    make CROSS_COMPILE=aarch64-linux-gnu- mt7981_emmc_rfb_defconfig
else
    echo "❌ mt7981_emmc_rfb_defconfig not found!"
    exit 1
fi

echo "CONFIG_MTK_FIP_SUPPORT=y" >> .config
make olddefconfig

make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ ! -f fip.bin ] && [ ! -f u-boot.fip ]; then
    echo "⚠️ fip.bin not generated, creating manually..."
    if [ -f "$FIPTOOL" ]; then
        "$FIPTOOL" create \
            --soc-fw $STAGING_DIR_IMAGE/mt7981-emmc-ddr4-bl31.bin \
            --nt-fw u-boot.bin \
            u-boot.fip
        cp u-boot.fip $OUTPUT_DIR/uboot/fip-emmc.bin
    else
        echo "❌ fiptool not found, cannot create FIP"
        exit 1
    fi
else
    cp fip.bin $OUTPUT_DIR/uboot/fip-emmc.bin 2>/dev/null || cp u-boot.fip $OUTPUT_DIR/uboot/fip-emmc.bin 2>/dev/null
fi
cp u-boot.bin $OUTPUT_DIR/uboot/u-boot-emmc.bin

# ========== 3. 准备 ImmortalWrt 源码 ==========
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 更新 feeds
echo "=== Updating feeds ==="
./scripts/feeds update -a

# ========== 4. 物理净化：批量删除依赖缺失的包 ==========
echo "=== Purging packages with missing dependencies ==="

# 删除所有依赖 rust/host 的包（根据日志中出现的包名）
RUST_DEPS_PKGS="aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server shadow-tls shadowsocks-rust spotifyd tuic-client tuic-server yggdrasil-jumper"
for pkg in $RUST_DEPS_PKGS; do
    rm -rf feeds/packages/$pkg
    rm -rf package/feeds/packages/$pkg
done

# 删除已知的其他问题包
rm -rf feeds/packages/gst1-plugins-base
rm -rf package/feeds/packages/gst1-plugins-base
rm -rf feeds/packages/onionshare-cli
rm -rf package/feeds/packages/onionshare-cli
rm -rf feeds/packages/onionshare
rm -rf package/feeds/packages/onionshare

# 删除整个 video 和 telephony feed（它们通常包含大量不需要的桌面软件）
rm -rf feeds/video
rm -rf feeds/telephony

# 重新生成 feed 索引
./scripts/feeds update -i

# 安装 feeds
./scripts/feeds install -a

# ========== 5. 自动注册三件套 (双路径注入 DTS) ==========
echo "=== 开始物理注册 SL3000 设备链 ==="

# 5.1 注入 DTS 文件到两个路径
mkdir -p $DTS_PATH_OLD
mkdir -p $DTS_PATH_NEW

echo "复制 DTS 到旧路径: $DTS_PATH_OLD"
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts $DTS_PATH_OLD/ || { echo "❌ 1G DTS copy to old path failed"; exit 1; }
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts $DTS_PATH_OLD/ || { echo "❌ 512M DTS copy to old path failed"; exit 1; }

echo "复制 DTS 到新内核专用路径: $DTS_PATH_NEW"
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-1g.dts $DTS_PATH_NEW/ || { echo "❌ 1G DTS copy to new path failed"; exit 1; }
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc-512m.dts $DTS_PATH_NEW/ || { echo "❌ 512M DTS copy to new path failed"; exit 1; }

# 5.2 注入设备定义文件
cp -v $CONFIG_DIR/mt7981.mk $MK_FILE || { echo "❌ mt7981.mk copy failed"; exit 1; }

# 验证设备定义是否已注册
if ! grep -q "sl_3000-emmc-1g" $MK_FILE; then
    echo "❌ 设备定义未成功写入 $MK_FILE"
    exit 1
fi
echo "✅ 设备定义已物理注册"

# 5.3 注入内核配置种子
cp -v $CONFIG_DIR/sl3000.config .config || { echo "❌ sl3000.config copy failed"; exit 1; }

# 5.4 强制启用您的设备
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-1g=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-512m=y" >> .config

# 5.5 重新生成配置
make defconfig

# 再次添加设备选项（defconfig 可能会重置）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-1g=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-512m=y" >> .config
make olddefconfig

# 5.6 最终验证设备是否启用
echo "=== 验证设备启用状态 ==="
grep "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-1g=y" .config || { echo "❌ 1G device not enabled!"; exit 1; }
grep "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc-512m=y" .config || { echo "❌ 512M device not enabled!"; exit 1; }
echo "✅ 设备已成功注册并启用"

# ========== 6. 编译 ImmortalWrt ==========
echo "=== Building ImmortalWrt ==="
make VERSION_NUMBER="1.0.0" VERSION_CODE="r1" -j$(nproc) V=s 2>&1 | tee build.log

# 列出并收集固件
echo "=== Listing generated images ==="
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -ls

echo "=== Collecting firmware ==="
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} $OUTPUT_DIR/firmware/ \;
cp build.log $OUTPUT_DIR/firmware/

# ========== 7. 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf $OUTPUT_DIR/mtk_uartboot.tar.gz .

# ========== 8. 最终输出 ==========
echo "✅ Build complete. Output directory contents:"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
