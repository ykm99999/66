# 司络 SL3000 路由器固件与救砖全家桶

## 硬件配置参数
| 组件 | 型号/规格 |
|------|----------|
| **SoC** | MediaTek MT7981B (Filogic 820) 双核 Cortex-A53 @ 1.3GHz |
| **无线芯片** | MT7976CN (2.4G/5G 双频，支持 802.11ax) |
| **内存** | 1GB DDR4 (型号: P3A8GL4MLF-GJN) |
| **eMMC 存储** | 128GB (型号: HSEMSDS7D2B128G) |
| **SPI NOR 闪存** | 32MB (型号: 25Q256FSSIG) |
| **网络接口** | 4×LAN, 1×WAN (均支持 2.5G) |

---

## 固件信息
- **基础系统**: ImmortalWrt 24.10 稳定版分支
- **内核版本**: Linux 6.6.x (基于官方补丁)
- **固件版本**: `v20260320` (或使用构建日期，示例: `v20250320`)
- **适用设备**: 司络 SL3000 (eMMC 版本)
- **集成软件包**:
  - LuCI 基础界面 (中文支持)
  - ksmbd (SMB 文件共享)
  - PassWall2 (代理管理)
  - Shadowsocks (libev/rust 版本)
  - Docker CE + docker-compose
  - 硬件加速 (Shortcut-FE / fast-classifier)
  - USB 3.0 支持
  - F2FS/EXT4 文件系统工具
  - 救砖辅助工具 (minicom, ttyd, uboot-envtools)

---

## 救砖全家桶文件列表
构建产物位于 `sl3000-firmware.zip` 中，包含以下关键文件：

| 文件 | 用途 | 说明 |
|------|------|------|
| `atf/bl2-512m-emmc.bin` | BL2 引导程序 (512MB 内存版) | **救砖首选**，通过串口加载到内存启动 |
| `atf/bl2-1g-emmc.bin` | BL2 引导程序 (1GB 内存版) | 正常启动或备用 |
| `atf/bl2-1g-nor.bin` | BL2 引导程序 (NOR 闪存版) | 用于编程器烧录至 SPI NOR |
| `uboot/fip-emmc.bin` | FIP 镜像 (BL31 + U-Boot) | **必须与 BL2 配合**，用于 eMMC 启动 |
| `uboot/fip-nor.bin` | FIP 镜像 (NOR 版) | 用于编程器烧录至 SPI NOR |
| `uboot/u-boot-emmc.bin` | U-Boot 本体 (eMMC) | 一般已包含在 FIP 中 |
| `uboot/u-boot-nor.bin` | U-Boot 本体 (NOR) | 一般已包含在 FIP 中 |
| `firmware/immortalwrt-mediatek-filogic-sl_3000-emmc-squashfs-sysupgrade.bin` | 系统升级固件 | 用于 Web 或 U-Boot 刷写 eMMC |
| `mtk_uartboot.tar.gz` | 串口救砖工具 | 包含 mtk_uartboot 可执行文件 |

---

## 快速构建指南
1. 克隆仓库并配置 GitHub Actions。
2. 修改 `888/` 目录下的三件套配置文件 (`mt7981-sl-3000-emmc.dts`, `sl3000.config`, `mt7981_sl3000.mk`)。
3. 手动触发 GitHub Actions 工作流。
4. 下载 Artifacts 中的 `sl3000-firmware.zip`。

---

## 救砖与刷机简要步骤

### 串口救砖 (eMMC 损坏)
1. 使用 CH340 模块 (3.3V 模式) 连接路由器 TTL 接口。
2. 在 Windows 命令行中运行:
   ```cmd
   mtk_uartboot.exe -s COM5 -p bl2-512m-emmc.bin -a -f fip-emmc.bin
