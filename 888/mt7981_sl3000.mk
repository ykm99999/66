# SPDX-License-Identifier: GPL-2.0-or-later

include ./common/common.mk

# -------------------------------------------------------------------
# 司络 SL3000 - SPI NOR 救砖引导镜像 (1GB DDR4 / 32MB NOR)
# -------------------------------------------------------------------
define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Rescue (1GB DDR4)
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-rescue

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | gzip

  # 生成 32MB 完整 SPI NOR 救砖镜像 (BL2 + FIP + 空环境变量)
  IMAGES := spi-rescue-32mb.bin
  IMAGE/spi-rescue-32mb.bin := gen_spi_rescue_image

  UBOOT_CONFIG := mt7981_spim_nor_rfb

  BLOCKSIZE := 128k
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear
endef

# -------------------------------------------------------------------
# 合成 32MB 救砖镜像 (仅引导部分，不含内核和 rootfs)
# -------------------------------------------------------------------
define Build/gen_spi_rescue_image
	# 1. 创建 32MB 容器，全填充 0xFF
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp

	# 2. 写入 BL2 (偏移 0x0)
	if [ -f $(BIN_DIR)/bl2.img ]; then \
		dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none; \
	else \
		echo "WARNING: bl2.img not found in $(BIN_DIR)"; \
	fi

	# 3. 写入 FIP (偏移 0x40000 = 256KB)
	if [ -f $(BIN_DIR)/fip.bin ]; then \
		dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=256k seek=1 conv=notrunc status=none; \
	else \
		echo "WARNING: fip.bin not found in $(BIN_DIR)"; \
	fi

	# 4. 擦除 U-Boot 环境变量区 (0xC0000 - 0x100000，共 256KB)
	dd if=/dev/zero bs=64k count=4 | tr '\000' '\377' | \
		dd of=$@.tmp bs=64k seek=12 conv=notrunc status=none

	mv $@.tmp $@
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
