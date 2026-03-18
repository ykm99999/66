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
MK_FILE="target/linux/mediatek/image/mt7981_sl3000.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 0. 验证三件套文件是否存在 ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981_sl3000.mk" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981_sl3000.mk"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/mt7981-sl-3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981-sl-3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# ========== 1. 编译 ATF ==========
cd $SOURCE_DIR/arm-trusted-firmware

echo "=== Building ATF 512M (EMMC) ==="
make clean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512
find build/mt7981/release -name "bl2*.bin" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.bin \; 2>/dev/null || echo "No bl2.bin for 512M emmc"
find build/mt7981/release -name "bl2*.elf" -exec cp {} $OUTPUT_DIR/atf/bl2-512m-emmc.elf \; 2>/dev/null || echo "No bl2.elf for 512M emmc"

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
./scripts/feeds update -a

# ========== 4. 彻底清除所有已知问题包 ==========
echo "=== 递归删除所有问题包 ==="

# 首先删除整个 telephony 和 video feed（它们包含大量问题包）
rm -rf feeds/telephony
rm -rf feeds/video

# 问题包列表（包含所有出现过依赖缺失的包）
PROBLEM_PKGS="
aardvark-dns
arp-whisper
bottom
cargo-c
clamav
dufs
eza
fish
lsd
netavark
pdns-recursor
procs
python-setuptools-rust
ripgrep
ruby
rust-bindgen
rustdesk-server
shadow-tls
shadowsocks-rust
shadowsocks-rust-sslocal
shadowsocks-rust-ssserver
spotifyd
tuic-client
tuic-server
yggdrasil-jumper
gst1-plugins-base
gst1-plugins-ugly
libdmapsharing
kamailio
smartdns
pymysql
python-orjson
python-paramiko
python-pyopenssl
python-rpds-py
python-service-identity
python-twisted
onionshare-cli
onionshare
weston
wpewebkit
luci-app-passwall
luci-app-rustdesk-server
luci-app-spotifyd
luci-app-clamav
luci-app-dufs
luci-app-openclash
luci-app-smartdns
libextractor
python-bcrypt
python-cryptography
python-maturin
podman
ruby-yaml
"

for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 清理 package/feeds 下的符号链接
rm -rf package/feeds

# 更新 feed 索引
./scripts/feeds update -i

# 安装 feeds（此时问题包已不存在）
./scripts/feeds install -a

# 再次递归删除（防止某些包因依赖被重新拉取）
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 再次更新索引并重建符号链接
./scripts/feeds update -i
make package/symlinks

# ========== 5. 注册三件套 ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1
cp -v $CONFIG_DIR/mt7981_sl3000.mk $MK_FILE || exit 1

if ! grep -q "sl_3000-emmc" $MK_FILE; then
    echo "❌ 设备定义未成功写入 $MK_FILE"
    exit 1
fi

cp -v $CONFIG_DIR/sl3000.config .config || exit 1
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

# ========== 6. 生成基础配置 ==========
make defconfig

# 再次写入设备选项（defconfig 可能会重置）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
make olddefconfig

# 验证设备是否在 .config 中启用
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ 设备 sl_3000-emmc 未在 .config 中启用！"
    exit 1
fi
echo "✅ 设备已启用"

# ========== 7. 编译 ImmortalWrt ==========
make VERSION_NUMBER="1.0.0" VERSION_CODE="r1" -j$(nproc) V=s 2>&1 | tee build.log

# 收集固件
mkdir -p $OUTPUT_DIR/firmware
find bin/targets/ -type f \( -name "*.bin" -o -name "*.img.gz" -o -name "*sysupgrade*" \) -exec cp -v {} $OUTPUT_DIR/firmware/ \;
cp build.log $OUTPUT_DIR/firmware/

# ========== 8. 打包 mtk_uartboot ==========
cd $SOURCE_DIR/mtk_uartboot
tar -czf $OUTPUT_DIR/mtk_uartboot.tar.gz .

echo "✅ Build complete. Output directory contents:"
ls -la $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware
