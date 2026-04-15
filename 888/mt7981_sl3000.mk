# SPDX-License-Identifier: GPL-2.0-or-later

include ./common/common.mk

# -------------------------------------------------------------------
# 司络 SL3000 - SPI NOR 1版物理救砖全家桶
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

  # 1版核心修复：不生成单独 GPT 文件，直接合成完整的 32MB 救砖包
  IMAGES := spi-full-32mb.bin
  IMAGE/spi-full-32mb.bin := gen_spi_full_image_v1

  # 指定 1GB DDR4 对应的 U-Boot 配置
  UBOOT_CONFIG := mt7981_sl3000_1g

  # 分区物理定义 (需与后续 dd 命令严格对齐)
  BLOCKSIZE := 128k
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear
endef

# -------------------------------------------------------------------
# 核心构建逻辑：1版像素级物理合成
# -------------------------------------------------------------------
define Build/gen_spi_full_image_v1
	# 1. 创建 32MB 纯净容器，填充 0xFF (防止旧分区表残留)
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp

	# 2. 写入 BL2 (必须在 0 偏移，使用针对 1G 内存的 NOR 版本)
	# 物理修复：原文照抄 bl2 素材到 0x0
	if [ -f $(BIN_DIR)/bl2-1g-nor.bin ]; then \
		dd if=$(BIN_DIR)/bl2-1g-nor.bin of=$@.tmp conv=notrunc status=none; \
	elif [ -f $(BIN_DIR)/bl2.img ]; then \
		dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none; \
	fi

	# 3. 物理修复：静默抹除 0x200 处的 GPT 毒药 (33个扇区)
	# 彻底断绝 117GB 逻辑冲突，让 U-Boot 只认 SPI NOR
	dd if=/dev/zero bs=512 count=33 | tr '\000' '\377' | \
	dd of=$@.tmp bs=512 seek=1 conv=notrunc status=none

	# 4. 写入 FIP (U-Boot) 到绝对对齐地址 0x40000 (256KB)
	# 物理修复：bs=256k seek=1 确保 TOC 标志出现在 0x40000
	if [ -f $(BIN_DIR)/fip.bin ]; then \
		dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=256k seek=1 conv=notrunc status=none; \
	fi

	# 5. 静默审计补丁：注入 9 秒拦截窗口
	# 防止默认 0 秒或 1 秒导致无法进入串口命令行
	sed -i 's/bootdelay=[0-9]/bootdelay=9/g' $@.tmp

	# 6. 静默审计：执行物理对齐二次检查
	# 如果 0x40000 处没有 TOC 标志，构建脚本将强制报错退出
	if ! dd if=$@.tmp bs=1 skip=262144 count=4 2>/dev/null | grep -q "TOC"; then \
		echo "FATAL ERROR: 0x40000 TOC signature not found! Alignment failed."; \
		exit 1; \
	fi

	mv $@.tmp $@
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
