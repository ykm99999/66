name: sl3000-firmware-V18-RESTORE

on:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-22.04
    env:
      DEBIAN_FRONTEND: noninteractive

    steps:
      - name: 1. 物理检出
        uses: actions/checkout@v4
        with:
          path: main-repo

      - name: 2. 源码克隆
        run: git clone --depth 1 https://github.com/immortalwrt/immortalwrt.git openwrt

      - name: 3. 环境初始化 (物理旁路工具)
        run: |
          sudo apt-get update
          sudo apt-get install -y gcc-aarch64-linux-gnu build-essential device-tree-compiler \
          bison flex m4 gawk gettext libncursesw5-dev libncurses5-dev zlib1g-dev \
          python3-setuptools swig python3-dev rsync unzip git qemu-utils libssl-dev \
          u-boot-tools

      - name: 4. 执行 diy-part1
        run: |
          cd openwrt
          [ -f ../main-repo/diy-part1.sh ] && chmod +x ../main-repo/diy-part1.sh && ../main-repo/diy-part1.sh
          ./scripts/feeds update -a
          ./scripts/feeds install -a

      - name: 5. 执行 diy-part2 (像素级修复)
        run: |
          cd openwrt
          cp -r ../main-repo/888 ../888
          chmod +x ../main-repo/diy-part2.sh
          ../main-repo/diy-part2.sh

      - name: 6. 物理配置锁定
        run: |
          cd openwrt
          make defconfig

      - name: 7. 物理编译 (伪造标记并绕过 mkimage)
        run: |
          cd openwrt
          # 物理旁路：注入宿主机 mkimage 并打桩
          mkdir -p staging_dir/host/bin
          cp -f /usr/bin/mkimage staging_dir/host/bin/mkimage
          chmod +x staging_dir/host/bin/mkimage
          mkdir -p staging_dir/host/stamp
          touch staging_dir/host/stamp/.mkimage_installed
          
          # 正式物理构建
          make tools/install -j$(nproc) || make tools/install -j1 V=s
          make toolchain/install -j$(nproc) || make toolchain/install -j1 V=s
          make target/linux/compile -j$(nproc) V=s

      - name: 8. 救砖包物理合成 (32MB)
        run: |
          mkdir -p output
          cd openwrt
          KERNEL_SRC=$(find bin/targets -name "*sysupgrade.itb" | head -n 1)
          RESCUE_BIN="../output/rescue-32.bin"
          REPO_888="../888"
          if [ -n "$KERNEL_SRC" ]; then
            dd if=/dev/zero bs=1M count=32 | tr '\000' '\377' > "$RESCUE_BIN"
            dd if="$REPO_888/bl2_orig.bin" of="$RESCUE_BIN" conv=notrunc status=none
            dd if="$REPO_888/fip_orig.bin" of="$RESCUE_BIN" bs=1M seek=1 conv=notrunc status=none
            dd if="$REPO_888/factory_orig.bin" of="$RESCUE_BIN" bs=1M seek=2 conv=notrunc status=none
            dd if="$KERNEL_SRC" of="$RESCUE_BIN" bs=1M seek=3 conv=notrunc status=none
          fi

      - name: 9. 物理整理：全量归档
        run: |
          mkdir -p publish_dir
          [ -f output/rescue-32.bin ] && cp output/rescue-32.bin publish_dir/
          find openwrt/bin/targets/ -type f \( -name "*.bin" -o -name "*.img*" -o -name "*.itb" -o -name "*.manifest" \) -exec cp {} publish_dir/ \;

      - name: 10. 自动发布 (V18 逻辑复刻)
        uses: softprops/action-gh-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: SL3000-V18-RESTORE-${{ github.run_id }}
          files: publish_dir/*
