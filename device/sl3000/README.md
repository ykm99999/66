# 司络 SL3000 完整源码与救砖配置

## 硬件参数（永久记录）
- **SoC**: MediaTek MT7981B (Filogic 820)
- **WiFi**: MT7976CN (DBDC)
- **RAM**: 1GB DDR4 (型号: P3A8GL4MLF-GJN)
- **eMMC**: 128GB (型号: HSEMSDS7D2B128G)
- **SPI NOR**: 32MB (型号: 25Q256FSSIG)

## 🔥 救砖关键步骤
1. **使用 mtk_uartboot 加载内存引导**：
   - 工具路径：`/mtk_uartboot`
   - 需要先编译 ATF 生成 `bl2.bin`（注意 DDR4 和 BGA 封装）
2. **内存降容救砖**：使用 512MB 配置的 BL2 引导（`DRAM_SIZE=512`）
3. **恢复 1GB 运行内存**：救砖成功后刷入正常 1GB 固件

## 分区布局（SPI NOR + eMMC）
- **SPI NOR (32MB)**: BL2, FIP, Factory (ART)
- **eMMC**: kernel, rootfs, rootfs_data, 用户存储

## ATF 编译参数
```bash
# 512MB 救砖版（DDR4, BGA）
make PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=512

# 1GB 正常版（DDR4, BGA）
make PLAT=mt7981 DEBUG=0 DDR3_FLY=0 USE_NMBM=0 BOOT_DEVICE=emmc LOG_LEVEL=20 DRAM_SIZE=1024
```

## U-Boot 编译参数
```make
make mt7981_sl3000_emmc_defconfig  # 需要自行创建此配置
```
