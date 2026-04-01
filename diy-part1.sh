#!/bin/bash
set -euo pipefail

# ========== 定义基础路径（使用绝对路径） ==========
WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"

DTS_PATH_OLD="target/linux/mediatek/dts"
DTS_PATH_NEW="target/linux/mediatek/files-6.6/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="$IMMORTALWRT_BUILD/target/linux/mediatek/image/filogic.mk"

# 创建输出目录
mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证配置文件 ==========
echo "=== 验证配置文件 ==="
if [ ! -f "$CONFIG_DIR/mt7981-sl-3000-emmc.dts" ]; then
    echo "❌ 缺少 $CONFIG_DIR/mt7981-sl-3000-emmc.dts"
    exit 1
fi
if [ ! -f "$CONFIG_DIR/sl3000.config" ]; then
    echo "❌ 缺少 $CONFIG_DIR/sl3000.config"
    exit 1
fi
echo "✅ 配置文件齐全"

# ========== 准备 ImmortalWrt 源码 ==========
cd $WORKSPACE
rm -rf immortalwrt-build
cp -r $SOURCE_DIR/immortalwrt immortalwrt-build
cd immortalwrt-build

# 修改 feeds 配置：禁用 telephony feed
sed -i 's/^src-git telephony/#src-git telephony/g' feeds.conf.default

# 添加 PassWall 系列 feeds（保留原有成功配置）
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

# 更新所有 feeds
./scripts/feeds update -a || { echo "❌ feeds update failed"; exit 1; }

# 确保 passwall2 feed 被正确拉取
if [ ! -d "feeds/passwall2" ]; then
    echo "❌ passwall2 feed failed to download. Please check the repository URL."
    exit 1
else
    echo "✅ passwall2 feed successfully updated"
fi

# ========== 定义问题包列表（与成功案例相同） ==========
PROBLEM_PKGS="
aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark
pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server
gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav
dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing
kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl
python-rpds-py python-service-identity python-twisted python-docker
python-jsonschema python-jsonschema-specifications python-referencing
onionshare-cli onionshare weston wpewebkit libextractor python-bcrypt python-cryptography
python-maturin podman ruby-yaml
"

# ========== 彻底清除所有已知问题包 ==========
echo "=== 递归删除所有问题包 ==="
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 删除整个 video 和 telephony feed
rm -rf feeds/video feeds/telephony

# 清理 package/feeds 下的符号链接
rm -rf package/feeds

# 更新 feed 索引
./scripts/feeds update -i || { echo "❌ feeds update -i failed"; exit 1; }

# 安装 feeds
./scripts/feeds install -a || { echo "❌ feeds install failed"; exit 1; }

# 再次递归删除（防止依赖重新拉取）
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 再次更新索引并重建符号链接
./scripts/feeds update -i || { echo "❌ feeds update -i failed"; exit 1; }
make package/symlinks || { echo "❌ make package/symlinks failed"; exit 1; }

# ========== 注册设备树（双路径） ==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# ========== 注入设备定义到 filogic.mk ==========
# 确保目标文件目录存在
mkdir -p "$(dirname "$FILOGIC_MK")"
touch "$FILOGIC_MK"

# 注入 eMMC 设备定义（原有成功配置）
echo "" >> "$FILOGIC_MK"
echo "# SL3000 eMMC 设备定义（由 diy-part1.sh 注入）" >> "$FILOGIC_MK"
echo "define Device/sl_3000-emmc" >> "$FILOGIC_MK"
echo "  DEVICE_VENDOR := SL" >> "$FILOGIC_MK"
echo "  DEVICE_MODEL := 3000 eMMC (1GB)" >> "$FILOGIC_MK"
echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$FILOGIC_MK"
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> "$FILOGIC_MK"
echo "  SUPPORTED_DEVICES := sl,3000-emmc" >> "$FILOGIC_MK"
echo "  DEVICE_PACKAGES := \\" >> "$FILOGIC_MK"
echo "    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \\" >> "$FILOGIC_MK"
echo "    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \\" >> "$FILOGIC_MK"
echo "    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \\" >> "$FILOGIC_MK"
echo "    luci-app-passwall2 \\" >> "$FILOGIC_MK"
echo "    xray-core chinadns-ng \\" >> "$FILOGIC_MK"
echo "    shadowsocks-libev-ss-local shadowsocks-libev-ss-redir shadowsocks-libev-ss-tunnel \\" >> "$FILOGIC_MK"
echo "    shadowsocks-rust-sslocal simple-obfs \\" >> "$FILOGIC_MK"
echo "    docker-ce docker-compose kmod-br-netfilter kmod-ikconfig kmod-ipt-physdev \\" >> "$FILOGIC_MK"
echo "    kmod-nf-ipt6 kmod-nf-ipvs kmod-veth kmod-fs-overlay luci-app-dockerman" >> "$FILOGIC_MK"
echo "  IMAGES := sysupgrade.bin" >> "$FILOGIC_MK"
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> "$FILOGIC_MK"
echo "endef" >> "$FILOGIC_MK"
echo "TARGET_DEVICES += sl_3000-emmc" >> "$FILOGIC_MK"

# 注入 SPI-NOR 救砖设备定义
echo "" >> "$FILOGIC_MK"
echo "# SL3000 SPI-NOR 救砖设备定义（由 diy-part1.sh 注入）" >> "$FILOGIC_MK"
echo "define Device/sl_3000-spi-nor" >> "$FILOGIC_MK"
echo "  DEVICE_VENDOR := SL" >> "$FILOGIC_MK"
echo "  DEVICE_MODEL := 3000 SPI-NOR (32MB)" >> "$FILOGIC_MK"
echo "  DEVICE_DTS := mt7981-sl-3000-emmc" >> "$FILOGIC_MK"
echo "  DEVICE_DTS_DIR := \$(DTS_DIR)" >> "$FILOGIC_MK"
echo "  SUPPORTED_DEVICES := sl,3000-spi-nor" >> "$FILOGIC_MK"
echo "  DEVICE_PACKAGES := \\" >> "$FILOGIC_MK"
echo "    kmod-usb3 kmod-usb-storage \\" >> "$FILOGIC_MK"
echo "    block-mount \\" >> "$FILOGIC_MK"
echo "    uboot-envtools \\" >> "$FILOGIC_MK"
echo "    ttyd" >> "$FILOGIC_MK"
echo "  IMAGES := sysupgrade.bin" >> "$FILOGIC_MK"
echo "  IMAGE_SIZE := 32768k" >> "$FILOGIC_MK"
echo "  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata" >> "$FILOGIC_MK"
echo "endef" >> "$FILOGIC_MK"
echo "TARGET_DEVICES += sl_3000-spi-nor" >> "$FILOGIC_MK"

# 验证设备定义是否已注入
if ! grep -q "sl_3000-spi-nor" "$FILOGIC_MK"; then
    echo "❌ 救砖设备定义未成功写入 $FILOGIC_MK"
    exit 1
fi
echo "✅ 设备定义已注入"

# ========== 配置 .config ==========
cp -v $CONFIG_DIR/sl3000.config .config || exit 1

# 设置基础平台
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config

# 同时启用两个设备
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# ========== 生成基础配置 ==========
make defconfig || { echo "❌ make defconfig failed"; exit 1; }

# 再次确保设备选项存在（defconfig 可能覆盖）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" >> .config

# ========== 使用 oldconfig 更新配置 ==========
echo "=== 运行 oldconfig（详细模式）==="
make -j1 V=s oldconfig 2>&1 | tee oldconfig.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ oldconfig 失败，错误日志如下（最后50行）："
    tail -50 oldconfig.log
    exit 1
fi

# ========== 最终验证设备是否在 .config 中启用 ==========
echo "=== 验证设备启用状态 ==="
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" .config; then
    echo "❌ eMMC 设备未启用！"
    exit 1
fi
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
    echo "❌ 救砖设备未启用！"
    exit 1
fi
echo "✅ 两个设备均已启用"

# 保存当前构建目录路径，供 part2 使用
echo $PWD > $WORKSPACE/build-dir.txt
