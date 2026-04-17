# SPDX-License-Identifier: GPL-2.0-or-later

include ./common/common.mk

define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Full (1GB DDR4 / 32MB NOR)
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-rescue

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | gzip

  # 生成完整的 32MB 镜像 (包含 5 个分区)
  IMAGES := spi-full-32mb.bin
  IMAGE/spi-full-32mb.bin := gen_spi_full_32mb

  UBOOT_CONFIG := mt7981_spim_nor_rfb

  BLOCKSIZE := 128k
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear
endef

# -------------------------------------------------------------------
# 合成 32MB 完整镜像 (BL2 + FIP + Factory + Kernel + RootFS)
# -------------------------------------------------------------------
define Build/gen_spi_full_32mb
	@echo "=== Synthesizing 32MB full image with 5 components ==="
	# 1. 创建 32MB 空容器，全部填充 0xFF
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp

	# 2. 写入 BL2 (偏移 0x0)
	if [ -f $(BIN_DIR)/bl2.img ]; then \
		dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none; \
		echo "  BL2 written at 0x000000"; \
	else \
		echo "  WARNING: bl2.img missing"; \
	fi

	# 3. 写入 FIP (偏移 0x40000 = 256KB)
	if [ -f $(BIN_DIR)/fip.bin ]; then \
		dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=256k seek=1 conv=notrunc status=none; \
		echo "  FIP written at 0x040000"; \
	else \
		echo "  WARNING: fip.bin missing"; \
	fi

	# 4. 写入 Factory (偏移 0x180000 = 1536KB = 1.5MB)
	if [ -f $(BIN_DIR)/factory.bin ]; then \
		dd if=$(BIN_DIR)/factory.bin of=$@.tmp bs=256k seek=6 conv=notrunc status=none; \
		echo "  Factory written at 0x180000"; \
	else \
		echo "  WARNING: factory.bin missing, Wi-Fi calibration will be blank"; \
	fi

	# 5. 写入 Kernel (偏移 0x1C0000 = 1792KB = 1.75MB)
	if [ -f $(BIN_DIR)/kernel.bin ]; then \
		dd if=$(BIN_DIR)/kernel.bin of=$@.tmp bs=256k seek=7 conv=notrunc status=none; \
		echo "  Kernel written at 0x1C0000"; \
	else \
		echo "  ERROR: kernel.bin missing"; \
		exit 1; \
	fi

	# 6. 写入 RootFS (偏移 0x5C0000 = 5888KB = 5.75MB)
	if [ -f $(BIN_DIR)/rootfs.bin ]; then \
		dd if=$(BIN_DIR)/rootfs.bin of=$@.tmp bs=256k seek=23 conv=notrunc status=none; \
		echo "  RootFS written at 0x5C0000"; \
	else \
		echo "  ERROR: rootfs.bin missing"; \
		exit 1; \
	fi

	mv $@.tmp $@
	echo "✅ Full 32MB image created: $@"
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
