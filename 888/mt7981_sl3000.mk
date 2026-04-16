# SPDX-License-Identifier: GPL-2.0-or-later

include ./common/common.mk

# -------------------------------------------------------------------
# 司络 SL3000 - SPI NOR 2版物理救砖全家桶 (1024MB RAM 适配)
# -------------------------------------------------------------------
define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Rescue (1GB DDR4 / 32MB NOR)
  # 物理锁定：确保引用适配 1024M 内存的设备树定义
  DEVICE_DTS := mt7981b-sl3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-rescue

  SOC := mt7981
  UBOOTENV_IN_FLASH := 1
  KERNEL_IN_UBI := 0

  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | gzip

  # 2版物理核心：生成 32MB 完整救砖镜像
  IMAGES := spi-full-32mb.bin
  IMAGE/spi-full-32mb.bin := gen_spi_full_image_v2

  # 物理映射：对应编译系统中已修复 200MHz 串口的 U-Boot 配置
  UBOOT_CONFIG := mt7981_spim_nor_rfb

  BLOCKSIZE := 128k
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear
endef

# -------------------------------------------------------------------
# 核心构建逻辑：2版像素级物理合成 (修正魔数校验)
# -------------------------------------------------------------------
define Build/gen_spi_full_image_v2
	# 1. 创建 32MB 物理容器，填充 0xFF (彻底清除干扰信号)
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp

	# 2. 写入 BL2 (必须位于 0 偏移，已通过 diy-part2.sh 锁定 1GB DDR4 初始化)
	if [ -f $(BIN_DIR)/bl2.img ]; then \
		dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none; \
	fi

	# 3. 物理屏蔽：清除 0x200 处的 GPT 逻辑坏块 (防止 U-Boot 误判存储介质)
	dd if=/dev/zero bs=512 count=33 | tr '\000' '\377' | \
	dd of=$@.tmp bs=512 seek=1 conv=notrunc status=none

	# 4. 写入 FIP (U-Boot)：绝对物理寻址锁定在 0x40000 (256KB)
	# 这对应你看到的特征码: 01 00 64 AA 78 56 34 12
	if [ -f $(BIN_DIR)/fip.bin ]; then \
		dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=256k seek=1 conv=notrunc status=none; \
	fi

	# 5. 像素级审计：检查 0x40000 处的 FIP 魔数 (78 56 34 12)
	# 这里的物理偏移 262148 = 262144 (0x40000) + 4 (跳过版本号)
	if ! dd if=$@.tmp bs=1 skip=262148 count=4 2>/dev/null | hexdump -ve '1/1 "%02x"' | grep -q "78563412"; then \
		echo "FATAL ERROR: 0x40000 FIP Magic Number mismatch! Check offset/alignment."; \
		exit 1; \
	fi

	# 6. 环境隔离：静默抹除 U-Boot Env 区域 (0xC0000)，强制系统使用默认救砖 IP 192.168.1.1
	dd if=/dev/zero bs=64k count=1 | tr '\000' '\377' | \
	dd of=$@.tmp bs=64k seek=12 conv=notrunc status=none

	echo "V2 Image Synthesis Complete: Physical alignment at 0x40000 verified."
	mv $@.tmp $@
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
