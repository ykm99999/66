#!/bin/bash
set -e

WORKSPACE="$GITHUB_WORKSPACE"
SOURCE_DIR="$WORKSPACE/source-repo"
CONFIG_DIR="$WORKSPACE/main-repo/888"
OUTPUT_DIR="$WORKSPACE/output"
IMMORTALWRT_BUILD="$WORKSPACE/immortalwrt-build"
STAGING_DIR_IMAGE="$IMMORTALWRT_BUILD/staging_dir/image"
DTS_PATH_OLD="target/linux/mediatek/dts"
# 自动探测内核版本对应的新 DTS 路径
KERNEL_VER=$(grep -E '^KERNEL_PATCHVER:=' target/linux/mediatek/Makefile | cut -d= -f2 | tr -d ' ')
[ -z "$KERNEL_VER" ] && KERNEL_VER="6.6"  # 默认使用 6.6（你的内核版本）
DTS_PATH_NEW="target/linux/mediatek/files-${KERNEL_VER}/arch/arm64/boot/dts/mediatek"
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

mkdir -p $OUTPUT_DIR/atf $OUTPUT_DIR/uboot $OUTPUT_DIR/firmware $STAGING_DIR_IMAGE

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ========== 验证三件套文件是否存在 ==========
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

# 添加 PassWall 系列 feeds
echo "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git" >> feeds.conf.default
echo "src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git" >> feeds.conf.default

# 更新所有 feeds
./scripts/feeds update -a

# 确保 passwall2 feed 被正确拉取
if [ ! -d "feeds/passwall2" ]; then
    echo "❌ passwall2 feed failed to download. Please check the repository URL."
    exit 1
else
    echo "✅ passwall2 feed successfully updated"
fi

# ========== 定义问题包列表（最终版）==========
PROBLEM_PKGS="
aardvark-dns arp-whisper bottom cargo-c clamav dufs eza fish lsd netavark
pdns-recursor procs python-setuptools-rust ripgrep ruby rust-bindgen rustdesk-server
shadow-tls spotifyd tuic-client tuic-server yggdrasil-jumper
gst1-plugins-base gst1-plugins-good gst1-plugins-ugly gst1-plugins-bad gst1-libav
dmapd gmediarender gnunet gnunet-fuse gnunet-fs grilo-plugins lcdgrilo libdmapsharing
kamailio smartdns pymysql python-orjson python-paramiko python-pyopenssl
python-rpds-py python-service-identity python-twisted python-docker
python-jsonschema python-jsonschema-specifications python-referencing
onionshare-cli onionshare weston wpewebkit luci-app-passwall
luci-app-rustdesk-server luci-app-spotifyd luci-app-clamav luci-app-dufs
luci-app-openclash luci-app-smartdns libextractor python-bcrypt python-cryptography
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
./scripts/feeds update -i

# 安装 feeds（此时问题包已不存在）
./scripts/feeds install -a

# 再次递归删除（防止依赖重新拉取）
for pkg in $PROBLEM_PKGS; do
    find feeds/ -type d -name "$pkg" -exec rm -rf {} \; 2>/dev/null || true
done

# 再次更新索引并重建符号链接
./scripts/feeds update -i
make package/symlinks

# ========== 注册三件套（设备树双路径注入 + 设备定义）==========
mkdir -p $DTS_PATH_OLD $DTS_PATH_NEW
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_OLD/ || exit 1
cp -v $CONFIG_DIR/mt7981-sl-3000-emmc.dts $DTS_PATH_NEW/ || exit 1

# 将设备定义追加到 filogic.mk（修正 DEVICE_DTS_DIR）
cat >> $FILOGIC_MK << 'EOF'

# SL3000 设备定义（由 diy-part1.sh 注入）
define Device/sl_3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := 3000 eMMC (1GB)
  DEVICE_DTS := mt7981-sl-3000-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)  # 修正：不加 /mediatek，避免路径重复
  SUPPORTED_DEVICES := sl,3000-emmc
  DEVICE_PACKAGES := \
    kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
    f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
    luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils \
    ~gst1-plugins-base \
    ~gst1-plugins-good \
    ~gst1-plugins-ugly \
    ~gst1-plugins-bad \
    ~gst1-libav \
    ~dmapd \
    ~gmediarender \
    ~gnunet \
    ~gnunet-fuse \
    ~gnunet-fs \
    ~grilo-plugins \
    ~lcdgrilo \
    ~libdmapsharing \
    ~kamailio \
    ~smartdns \
    ~pymysql \
    ~python-orjson \
    ~python-paramiko \
    ~python-pyopenssl \
    ~python-rpds-py \
    ~python-service-identity \
    ~python-twisted \
    ~python-docker \
    ~python-jsonschema \
    ~python-jsonschema-specifications \
    ~python-referencing \
    ~luci-app-passwall \
    ~luci-app-rustdesk-server \
    ~luci-app-spotifyd \
    ~luci-app-clamav \
    ~luci-app-dufs \
    ~luci-app-openclash \
    ~luci-app-smartdns \
    ~libextractor \
    ~python-bcrypt \
    ~python-cryptography \
    ~python-maturin \
    ~python-setuptools-rust \
    ~podman \
    ~ruby \
    ~ruby-yaml \
    ~aardvark-dns \
    ~netavark \
    ~pdns-recursor \
    ~cargo-c \
    ~arp-whisper \
    ~yggdrasil-jumper \
    ~onionshare-cli \
    ~onionshare \
    ~weston \
    ~wpewebkit \
    ~shadowsocks-rust \
    ~shadowsocks-rust-sslocal \
    ~shadowsocks-rust-ssserver \
    ~shadow-tls \
    ~tuic-client \
    ~tuic-server \
    ~rustdesk-server \
    ~spotifyd \
    ~clamav \
    ~dufs \
    ~eza \
    ~fish \
    ~lsd \
    ~bottom \
    ~ripgrep \
    ~procs
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sl_3000-emmc
EOF

# 验证设备定义是否已注入
if ! grep -q "sl_3000-emmc" $FILOGIC_MK; then
    echo "❌ 设备定义未成功写入 $FILOGIC_MK"
    exit 1
fi

cp -v $CONFIG_DIR/sl3000.config .config || exit 1
echo "CONFIG_TARGET_mediatek=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

# ========== 生成基础配置 ==========
make defconfig

# 再次写入设备选项（确保存在）
echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-emmc=y" >> .config

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
    echo "❌ 设备 sl_3000-emmc 未在 .config 中启用！"
    exit 1
fi
echo "✅ 设备已启用"

# 保存当前构建目录路径，供 part2 使用
echo $PWD > $WORKSPACE/build-dir.txt
