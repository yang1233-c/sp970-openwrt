#!/bin/sh
set -eu

OPENWRT_DIR=${1:-${Q410_OPENWRT_TREE:-$HOME/q410/openwrt-25.12.5}}
KERNEL_BASE="$OPENWRT_DIR/build_dir/target-aarch64_cortex-a53_musl/linux-msm89xx_msm8916"
KERNEL_DIR=$(find "$KERNEL_BASE" -mindepth 1 -maxdepth 1 -type d \
	-name 'linux-[0-9]*' | head -n 1)
TOOLCHAIN_DIR=$(find "$OPENWRT_DIR/staging_dir" -maxdepth 1 -type d \
	-name 'toolchain-aarch64_cortex-a53_*' | head -n 1)

[ -n "$KERNEL_DIR" ]
[ -n "$TOOLCHAIN_DIR" ]
export PATH="$TOOLCHAIN_DIR/bin:$PATH"

BOARD_DTS="$OPENWRT_DIR/target/linux/msm89xx/files-6.12/arch/arm64/boot/dts/qcom/msm8916-gexing-sp970.dts"
KERNEL_DTS="$KERNEL_DIR/arch/arm64/boot/dts/qcom/msm8916-gexing-sp970.dts"
[ -s "$BOARD_DTS" ]
cp "$BOARD_DTS" "$KERNEL_DTS"

make -C "$KERNEL_DIR" \
	ARCH=arm64 \
	CROSS_COMPILE=aarch64-openwrt-linux-musl- \
	qcom/msm8916-gexing-sp970.dtb

DTB="$KERNEL_DIR/arch/arm64/boot/dts/qcom/msm8916-gexing-sp970.dtb"
[ -s "$DTB" ]
printf '%s\n' "$DTB"
