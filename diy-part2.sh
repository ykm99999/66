name: SL3000 Final Build with Auto Release

on:
  workflow_dispatch:
  push:
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: ubuntu-22.04
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
    steps:
      - name: Checkout main branch
        uses: actions/checkout@v4
        with:
          ref: main
          path: main-repo

      - name: Checkout source branch
        uses: actions/checkout@v4
        with:
          repository: ykm99999/66
          ref: sl3000-full-sync
          path: source-repo

      - name: Generate release tag
        id: release_tag
        run: |
          TAG_NAME="v$(date -u +'%Y%m%d-%H%M%S')"
          echo "tag_name=$TAG_NAME" >> $GITHUB_OUTPUT
          echo "Release tag: $TAG_NAME"

      - name: Install dependencies
        run: |
          sudo apt update
          sudo apt install -y build-essential clang flex bison gawk \
            gettext git libncurses-dev libssl-dev \
            python3-distutils python3-setuptools rsync unzip zlib1g-dev file wget \
            gcc-aarch64-linux-gnu device-tree-compiler

      - name: Optimize disk space
        run: |
          sudo apt clean
          sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/lib/android
          df -h

      - name: Verify required files
        run: |
          echo "Checking required configuration files..."
          if [ ! -f "main-repo/888/sl3000.config" ]; then
            echo "❌ sl3000.config not found in main-repo/888/"
            exit 1
          fi
          if [ ! -f "main-repo/888/mt7981-sl-3000-emmc.dts" ]; then
            echo "❌ mt7981-sl-3000-emmc.dts not found in main-repo/888/"
            exit 1
          fi
          echo "✅ All required files present."

      - name: Run diy-part1.sh (Configuration & Package Purge)
        run: |
          chmod +x main-repo/diy-part1.sh
          cd main-repo
          ./diy-part1.sh

      - name: Verify target device enabled
        run: |
          cd main-repo/immortalwrt-build
          if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl_3000-spi-nor=y" .config; then
            echo "❌ Target device sl_3000-spi-nor is not enabled in .config!"
            exit 1
          fi
          echo "✅ Target device sl_3000-spi-nor is enabled."

      - name: Run diy-part2.sh (Compile)
        run: |
          chmod +x main-repo/diy-part2.sh
          cd main-repo
          ./diy-part2.sh

      - name: List firmware files
        run: |
          echo "=== Generated files ==="
          ls -la output/atf/ output/uboot/ output/firmware/ || true
          echo "=== Firmware directory contents ==="
          find output/ -type f \( -name "*.bin" -o -name "*.gz" -o -name "*sysupgrade*" \) | sort

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.release_tag.outputs.tag_name }}
          name: "SL3000 Rescue Firmware ${{ steps.release_tag.outputs.tag_name }}"
          body: |
            ## 自动构建的 SL3000 救砖全家桶
            - 构建时间: ${{ steps.release_tag.outputs.tag_name }}
            - 目标设备: SL-3000 SPI-NOR 救砖镜像 (32MB)
            - 包含软件: PassWall2, Shadowsocks, 基础网络支持

            ### 📦 下载说明
            - `firmware/Spi-flash-32MB.bin` 为完整的 SPI-NOR 救砖固件，可通过 `mtk_uartboot` 或编程器刷入。
            - `atf/` 目录包含 DDR4 版本的 ATF BL2/31 文件（NOR 版）。
            - `uboot/` 目录包含 U-Boot 及 FIP 镜像（NOR 版）。
            - `mtk_uartboot.tar.gz` 为串口救砖工具包。

            > ⚠️ 注意：此固件专为从 SPI-NOR 启动设计，用于救援系统或作为最小化恢复环境。刷写前请确认您的设备具有 32MB SPI-NOR 闪存。
          files: |
            output/atf/*.bin
            output/atf/*.elf
            output/uboot/*.bin
            output/firmware/Spi-flash-32MB.bin
            output/mtk_uartboot.tar.gz
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Upload artifacts (backup)
        uses: actions/upload-artifact@v4
        with:
          name: sl3000-rescue-${{ steps.release_tag.outputs.tag_name }}
          path: |
            output/atf/
            output/uboot/
            output/firmware/Spi-flash-32MB.bin
            output/mtk_uartboot.tar.gz
          if-no-files-found: error
