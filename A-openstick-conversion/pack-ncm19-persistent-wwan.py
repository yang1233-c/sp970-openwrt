#!/usr/bin/env python3
"""Pack a persistent p12 boot image and fixed-size rollback-friendly payload."""

from hashlib import sha1, sha256
from json import dumps
from os import environ
from pathlib import Path
from struct import pack, pack_into, unpack_from

ROOT = Path(environ.get("Q410_WORKSPACE", Path(__file__).resolve().parents[1]))
BASE = ROOT / (
    "artifacts/A-SP970-openwrt-25.12.5-initramfs-20260810/"
    "A-SP970-OpenWrt-25.12.5-initramfs-ncm19-led2-status-leds-lk1st.img"
)
KERNEL = ROOT / environ.get(
    "Q410_PERSISTENT_KERNEL",
    "artifacts/A-SP970-persistent-wwan-20260811/kernel-persistent.bin.gz",
)
ROOTFS = ROOT / environ.get(
    "Q410_PERSISTENT_ROOTFS",
    "artifacts/A-SP970-persistent-wwan-20260811/rootfs-payload-256MiB.ext4",
)
OUT_DIR = ROOT / "artifacts/A-SP970-persistent-wwan-20260811"
BOOT_IMAGE = OUT_DIR / "boot-persistent-lk1st.img"
BOOT_PAYLOAD = OUT_DIR / "boot-payload-64MiB.bin"
MANIFEST = ROOT / "manifests/q410-ncm19-persistent-wwan.json"

EXPECTED_BASE = "E3A2B3D1847314B13ED81410E7EA824D613B6EAD2992ED1C857EDA792AC61150"
BOOT_PARTITION_BYTES = 64 * 1024 * 1024
ROOTFS_WRITE_BYTES = 256 * 1024 * 1024
CMDLINE = (
    "earlycon console=ttyMSM0,115200n8 root=/dev/mmcblk0p14 "
    "rootfstype=ext4 rootwait rw no_framebuffer=true"
)


def hash_hex(blob: bytes) -> str:
    return sha256(blob).hexdigest().upper()


base = BASE.read_bytes()
if hash_hex(base) != EXPECTED_BASE:
    raise SystemExit("NCM19 LED2 base hash mismatch")
kernel_gzip = KERNEL.read_bytes()
rootfs = ROOTFS.read_bytes()
if len(rootfs) != ROOTFS_WRITE_BYTES:
    raise SystemExit("rootfs payload is not exactly 256 MiB")

kernel_size, _, ramdisk_size, _, second_size, _, _, page_size, dt_size, _ = unpack_from(
    "<10I", base, 8
)
if base[:8] != b"ANDROID!" or ramdisk_size or second_size or dt_size:
    raise SystemExit("unexpected Android boot layout")
old_kernel = base[page_size : page_size + kernel_size]
dtb_at = old_kernel.find(b"\xd0\x0d\xfe\xed")
if dtb_at < 1:
    raise SystemExit("SP970 appended DTB tail missing")
tail = old_kernel[dtb_at:]
kernel = kernel_gzip + tail

header = bytearray(base[:page_size])
pack_into("<I", header, 8, len(kernel))
header[48:64] = b"SP970-PW26" + b"\0" * 6
cmdline = CMDLINE.encode("ascii")
if len(cmdline) >= 512:
    raise SystemExit("boot cmdline too long")
header[64:576] = cmdline + b"\0" * (512 - len(cmdline))
digest = sha1()
for payload in (kernel, b"", b""):
    digest.update(payload)
    digest.update(pack("<I", len(payload)))
header[576:608] = digest.digest() + b"\0" * 12

boot = header + kernel
boot += b"\0" * ((-len(boot)) % page_size)
if len(boot) > BOOT_PARTITION_BYTES:
    raise SystemExit("boot image exceeds p12")
boot_payload = boot + b"\0" * (BOOT_PARTITION_BYTES - len(boot))
OUT_DIR.mkdir(parents=True, exist_ok=True)
BOOT_IMAGE.write_bytes(boot)
BOOT_PAYLOAD.write_bytes(boot_payload)

manifest = {
    "schema": "q410-ncm19-persistent-wwan-v1",
    "base_image": str(BASE),
    "base_image_sha256": EXPECTED_BASE,
    "kernel_gzip": str(KERNEL),
    "kernel_gzip_bytes": len(kernel_gzip),
    "kernel_gzip_sha256": hash_hex(kernel_gzip),
    "dtb_tail_bytes": len(tail),
    "dtb_tail_sha256": hash_hex(tail),
    "cmdline": CMDLINE,
    "boot_image": str(BOOT_IMAGE),
    "boot_image_bytes": len(boot),
    "boot_image_sha256": hash_hex(boot),
    "boot_payload": str(BOOT_PAYLOAD),
    "boot_payload_bytes": len(boot_payload),
    "boot_payload_sha256": hash_hex(boot_payload),
    "boot_target": "/dev/mmcblk0p12",
    "rootfs_payload": str(ROOTFS),
    "rootfs_payload_bytes": len(rootfs),
    "rootfs_payload_sha256": hash_hex(rootfs),
    "rootfs_target": "/dev/mmcblk0p14",
    "rootfs_write_offset": 0,
    "nv_policy": "rmtfs -P -r read-only shadow",
    "write_order": ["rootfs", "rootfs-readback", "boot", "boot-readback"],
    "preimage_required": {
        "/dev/mmcblk0p12": BOOT_PARTITION_BYTES,
        "/dev/mmcblk0p14": ROOTFS_WRITE_BYTES,
    },
}
MANIFEST.parent.mkdir(parents=True, exist_ok=True)
MANIFEST.write_text(dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("PERSISTENT_BOOT_PACK_PASS")
print(f"BOOT_IMAGE_SHA256={manifest['boot_image_sha256']}")
print(f"BOOT_PAYLOAD_SHA256={manifest['boot_payload_sha256']}")
print(f"ROOTFS_SHA256={manifest['rootfs_payload_sha256']}")
print(f"MANIFEST={MANIFEST}")
