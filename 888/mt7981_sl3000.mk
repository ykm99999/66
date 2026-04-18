cat <<'EOF' > 888/mt7981_sl3000.mk
# SPDX-License-Identifier: GPL-2.0-or-later

# 物理修复：移除 include ./common/common.mk，改为自包含模式

define Device/mt7981_sl3000_spi_rescue
  DEVICE_VENDOR := Siluo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := SPI Full (1GB DDR4 / 32MB NOR)
  DEVICE_DTS := mt7981b-sl-3000-emmc
  SUPPORTED_DEVICES := siluo,sl3000-spi-rescue
  DEVICE_DRAM_SIZE := 1024M

  SOC := mt7981
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  
  # 救砖包核心：生成 32MB 完整镜像
  IMAGES := spi-full-32mb.bin
  IMAGE/spi-full-32mb.bin := append-kernel | pad-to 32M
  
  DEVICE_PACKAGES := \
    uboot-envtools mtd-utils kmod-mtd-rw \
    block-mount kmod-mmc kmod-mmc-mtk \
    kmod-fs-ext4 kmod-fs-f2fs f2fs-tools e2fsprogs \
    ip-full dropbear
endef

# 重新定义物理合成逻辑，确保偏移量与 DTS (0x300000) 绝对同步
define Build/gen_spi_full_32mb
	@echo "=== 物理审计：正在合成 32MB 救砖镜像 ==="
	dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > $@.tmp
	
	# 物理偏移对齐：
	# 0M -> BL2
	# 1M -> FIP (0x100000)
	# 2M -> Factory (0x200000)
	# 3M -> Firmware/Kernel (0x300000)
	
	[ -f $(BIN_DIR)/bl2.img ] && dd if=$(BIN_DIR)/bl2.img of=$@.tmp conv=notrunc status=none
	[ -f $(BIN_DIR)/fip.bin ] && dd if=$(BIN_DIR)/fip.bin of=$@.tmp bs=1M seek=1 conv=notrunc status=none
	[ -f $(BIN_DIR)/factory.bin ] && dd if=$(BIN_DIR)/factory.bin of=$@.tmp bs=1M seek=2 conv=notrunc status=none
	[ -f $(KDIR)/fit-mt7981b-sl-3000-emmc.itb ] && dd if=$(KDIR)/fit-mt7981b-sl-3000-emmc.itb of=$@.tmp bs=1M seek=3 conv=notrunc status=none
	
	mv $@.tmp $@
	@echo "✅ 32MB 救砖镜像合成成功"
endef

TARGET_DEVICES += mt7981_sl3000_spi_rescue
EOF
