#!/usr/bin/env bash
set -euo pipefail

ow="${Q410_OPENWRT_TREE:-$HOME/q410/openwrt-25.12.5}"
workspace="${Q410_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
target="$ow/build_dir/target-aarch64_cortex-a53_musl"
kernel="$target/linux-msm89xx_msm8916/linux-6.12.94"
root="$target/root-msm89xx"
out="$workspace/artifacts/A-SP970-persistent-wwan-20260811"
aux="$workspace/artifacts/A-SP970-modem-aux-runtime-20260811"
firmware="${Q410_FIRMWARE_DIR:-$HOME/q410/local-firmware/sp970}"
make_ext4fs="$ow/staging_dir/host/bin/make_ext4fs"
e2fsck_bin="$ow/staging_dir/host/bin/e2fsck"
debugfs_bin="$ow/staging_dir/host/bin/debugfs"
rootfs_bytes=268435456
wcn_builtin_firmware='wcnss.mdt wcnss.b00 wcnss.b01 wcnss.b02 wcnss.b04 wcnss.b06 wcnss.b09 wcnss.b10 wcnss.b11'

test -x "$kernel/scripts/config"
test -d "$root"
test -x "$make_ext4fs"
test -x "$e2fsck_bin"
test -x "$debugfs_bin"
test -d "$firmware"
test -x "$root/usr/bin/qmicli"
test -x "$root/usr/sbin/rmtfs"
test -x "$aux/tqftpserv"
test -x "$aux/qrtr-lookup"

mkdir -p "$out" "$root/usr/bin" "$root/usr/sbin" \
  "$root/lib/firmware" "$root/etc/rc.d"

# Freeze the tested workspace overlay and modem runtime into the production root.
cp -a "$workspace/sp970-openwrt-build/files/." "$root/"
install -m 0755 "$aux/tqftpserv" "$root/usr/bin/tqftpserv"
install -m 0755 "$aux/qrtr-lookup" "$root/usr/bin/qrtr-lookup"
install -m 0755 "$workspace/sp970-openwrt-build/files/usr/sbin/sp970-rmtfs-start" \
  "$root/usr/sbin/sp970-rmtfs-start"
install -m 0755 "$workspace/sp970-openwrt-build/files/usr/sbin/sp970-modem-led" \
  "$root/usr/sbin/sp970-modem-led"
install -m 0755 "$workspace/sp970-openwrt-build/files/etc/init.d/sp970-modem" \
  "$root/etc/init.d/sp970-modem"
ln -sfn ../init.d/sp970-modem "$root/etc/rc.d/S14sp970-modem"
cp -a "$firmware/." "$root/lib/firmware/"

# The resulting tree must contain every binary, ABI and firmware family used by
# the successful RAM QMI test.  The check is deliberately explicit.
for required in \
  sbin/init usr/bin/qmicli usr/sbin/rmtfs usr/bin/tqftpserv \
  usr/sbin/q410-qmi-uim-provision usr/sbin/q410-qmi-wds-connect \
  usr/sbin/sp970-rmtfs-start usr/sbin/sp970-modem-led \
  etc/init.d/sp970-modem etc/rc.d/S14sp970-modem \
  usr/lib/libqmi-glib.so.5 usr/lib/libqrtr-glib.so.0 \
  usr/lib/libglib-2.0.so.0; do
  test -e "$root/$required"
done
find "$root/lib/firmware" -type f | grep -Eq '/(mba|modem|wcnss|venus|qcom)/|\.mbn$|\.mdt$|\.b[0-9][0-9]$'

export PATH="$ow/staging_dir/toolchain-aarch64_cortex-a53_gcc-14.3.0_musl/bin:/usr/bin:/bin"
export STAGING_DIR="$ow/staging_dir"
export ARCH=arm64
export CROSS_COMPILE=aarch64-openwrt-linux-musl-

cd "$kernel"
scripts/config --enable QCOM_RMTFS_MEM --enable QCOM_PD_MAPPER \
  --enable RPMSG_WWAN_CTRL --enable EXT4_FS \
  --enable DEVTMPFS --enable DEVTMPFS_MOUNT
scripts/config --set-str INITRAMFS_SOURCE ""
scripts/config --set-str EXTRA_FIRMWARE "$wcn_builtin_firmware"
scripts/config --set-str EXTRA_FIRMWARE_DIR "$root/lib/firmware"
make olddefconfig
grep -qx 'CONFIG_QCOM_RMTFS_MEM=y' .config
grep -qx 'CONFIG_QCOM_PD_MAPPER=y' .config
grep -qx 'CONFIG_RPMSG_WWAN_CTRL=y' .config
grep -qx 'CONFIG_EXT4_FS=y' .config
grep -qx 'CONFIG_DEVTMPFS=y' .config
grep -qx 'CONFIG_DEVTMPFS_MOUNT=y' .config
grep -qx 'CONFIG_INITRAMFS_SOURCE=""' .config
grep -Fqx "CONFIG_EXTRA_FIRMWARE=\"$wcn_builtin_firmware\"" .config
grep -Fqx "CONFIG_EXTRA_FIRMWARE_DIR=\"$root/lib/firmware\"" .config
cp .config "$out/kernel-persistent.config"
rm -f usr/initramfs_data.cpio usr/initramfs_inc_data usr/initramfs_data.o \
  usr/built-in.a arch/arm64/boot/Image
make -j"${Q410_BUILD_JOBS:-$(nproc)}" Image
gzip -n -9 -c arch/arm64/boot/Image > "$out/kernel-persistent.bin.gz"

rm -f "$out/rootfs-payload-256MiB.ext4"
"$make_ext4fs" -L rootfs -l "$rootfs_bytes" -b 4096 -m 0 -T 0 \
  "$out/rootfs-payload-256MiB.ext4" "$root/"
test "$(stat -c %s "$out/rootfs-payload-256MiB.ext4")" -eq "$rootfs_bytes"
# make_ext4fs leaves unused bitmap tail bits clear; normalize them once, then
# require a clean read-only verification before the image can be packed.
set +e
"$e2fsck_bin" -fy "$out/rootfs-payload-256MiB.ext4"
e2fsck_fix_rc=$?
set -e
if [ "$e2fsck_fix_rc" -gt 1 ]; then
  exit "$e2fsck_fix_rc"
fi
"$e2fsck_bin" -fn "$out/rootfs-payload-256MiB.ext4"
"$debugfs_bin" -R 'stat /sbin/init' "$out/rootfs-payload-256MiB.ext4" 2>&1 | grep -q 'Inode:'
"$debugfs_bin" -R 'stat /usr/bin/qmicli' "$out/rootfs-payload-256MiB.ext4" 2>&1 | grep -q 'Inode:'
"$debugfs_bin" -R 'stat /usr/sbin/rmtfs' "$out/rootfs-payload-256MiB.ext4" 2>&1 | grep -q 'Inode:'
"$debugfs_bin" -R 'stat /etc/rc.d/S14sp970-modem' "$out/rootfs-payload-256MiB.ext4" 2>&1 | grep -q 'Inode:'

Q410_WORKSPACE="$workspace" \
Q410_PERSISTENT_KERNEL="artifacts/A-SP970-persistent-wwan-20260811/kernel-persistent.bin.gz" \
Q410_PERSISTENT_ROOTFS="artifacts/A-SP970-persistent-wwan-20260811/rootfs-payload-256MiB.ext4" \
python3 "$workspace/A-openstick-conversion/pack-ncm19-persistent-wwan.py"

sha256sum \
  "$out/kernel-persistent.bin.gz" \
  "$out/rootfs-payload-256MiB.ext4" \
  "$out/boot-persistent-lk1st.img" \
  "$out/boot-payload-64MiB.bin" | tee "$out/SHA256SUMS"
echo PERSISTENT_WWAN_BUILD_PASS
