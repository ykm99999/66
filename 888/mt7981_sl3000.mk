# SPDX-License-Identifier: GPL-2.0-or-later

include ./common/common.mk

# -------------------------------------------------------------------
# 司络 SL3000 - SPI NOR 救援模式 (无 eMMC 启动，纯 SPI 启动)
# -------------------------------------------------------------------
define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Rescue (1GB DDR4 / 32MB NOR)
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-rescue

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | gzip

  # 确保只构建救援相关组件，不生成完整 rootfs
  IMAGES := gpt.bin spi-full-32mb.bin
  IMAGE/gpt.bin := gen_spi_gpt
  IMAGE/spi-full-32mb.bin := gen_spi_full_image

  # 定义 SPI NOR 分区布局 (与 GPT 表一致)
  # 注意：这里的分区定义仅用于 OpenWrt 内部记录，实际写入 Flash 由 GPT 决定
  # 偏移地址参考 MT7981 常见 SPI 布局
  BLOCKSIZE := 128k
  BL2_OFFSET := 0x00000000
  BL2_SIZE := 0x00040000      # 256KB (实际通常更小)
  FIP_OFFSET := 0x00040000
  FIP_SIZE := 0x001C0000      # 1.75MB (包含 ATF BL31 + U-Boot)
  UBOOTENV_OFFSET := 0x00200000
  UBOOTENV_SIZE := 0x00020000 # 128KB
  KERNEL_OFFSET := 0x00220000
  KERNEL_SIZE := 0x00C00000   # 12MB (示例)
  ROOTFS_OFFSET := 0x00E20000
  ROOTFS_SIZE := 0x011E0000   # 剩余空间 (约 18MB)

  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear \
    kmod-leds-gpio kmod-button-hotplug
endef

# -------------------------------------------------------------------
# 生成 GPT 分区表的脚本 (依赖 host-parted 和 host-sgdisk)
# -------------------------------------------------------------------
define Build/gen_spi_gpt
  # 创建一个空的 32MB 镜像并写入 GPT 分区表
  rm -f $@.tmp
  dd if=/dev/zero of=$@.tmp bs=1M count=32 status=none
  # 使用 sgdisk 创建分区 (扇区大小 512 字节)
  sgdisk -o $@.tmp
  sgdisk -n 1:0:+256K  -c 1:"bl2"        -t 1:8301 $@.tmp
  sgdisk -n 2:0:+1792K -c 2:"fip"        -t 2:8302 $@.tmp
  sgdisk -n 3:0:+128K  -c 3:"u-boot-env" -t 3:8303 $@.tmp
  sgdisk -n 4:0:+12M   -c 4:"kernel"     -t 4:8304 $@.tmp
  sgdisk -n 5:0:0      -c 5:"rootfs"     -t 5:8305 $@.tmp
  # 提取纯 GPT 表 (前 34 个扇区)
  dd if=$@.tmp of=$@ bs=512 count=34 conv=fsync status=none
  rm -f $@.tmp
endef

# -------------------------------------------------------------------
# 生成完整的 32MB SPI Flash 救援镜像
# -------------------------------------------------------------------
define Build/gen_spi_full_image
  # 1. 创建 32MB 空白文件，填充 0xFF (Flash 擦除态)
  dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp

  # 2. 写入 GPT 表 (前 34 扇区)
  dd if=$(word 1,$^) of=$@.tmp bs=512 seek=0 conv=notrunc status=none

  # 3. 写入 BL2 (由 ATF 包生成，位于 bl2.img)
  if [ -f $(BIN_DIR)/bl2.img ]; then \
    dd if=$(BIN_DIR)/bl2.img of=$@.tmp bs=256k seek=0 conv=notrunc status=none; \
  fi

  # 4. 写入 FIP (包含 BL31 + U-Boot)
  if [ -f $(BIN_DIR)/fip.bin ]; then \
    dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=256k seek=1 conv=notrunc status=none; \
  fi

  # 5. 创建空的 U-Boot 环境变量区域 (128KB，全 0xFF)
  dd if=/dev/zero bs=128k count=1 | tr '\000' '\377' > $@.env
  dd if=$@.env of=$@.tmp bs=128k seek=16 conv=notrunc status=none
  rm -f $@.env

  # 6. 最终输出
  mv $@.tmp $@
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
