#!/usr/bin/env python3
"""Package an AArch64 kernel, optional external ramdisk and DTB as boot v0.

The result is intended for a RAM-only validation gate. It never opens a device
node and stops before producing an image larger than the captured 16 MiB boot
partition by default.
"""
from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

PAGE = 2048
SP970_QCDT_V2_IDS = (206, 248, 249, 250)


def pad(data: bytes, page: int = PAGE) -> bytes:
    return data + b"\0" * ((-len(data)) % page)


def make_sp970_qcdt_v2(dtb: bytes) -> bytes:
    """Build the QCDT v2 wrapper used by A's captured factory boot image."""
    dtb_blob = pad(dtb)
    dtb_offset = PAGE
    entries = b"".join(
        struct.pack("<6I", platform_id, 8, 1, 0, dtb_offset, len(dtb_blob))
        for platform_id in SP970_QCDT_V2_IDS
    )
    table = b"QCDT" + struct.pack("<2I", 2, len(SP970_QCDT_V2_IDS)) + entries
    table += struct.pack("<I", 0)
    return pad(table) + dtb_blob


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", type=Path, required=True)
    ap.add_argument("--ramdisk", type=Path)
    ap.add_argument("--dtb", type=Path, required=True)
    ap.add_argument(
        "--dtb-mode",
        choices=("header", "append-kernel", "qcdt-v2"),
        default="header",
        help="place a raw DTB in the Android dt section or append it to the kernel payload",
    )
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--cmdline", default="console=ttyMSM0,115200 earlycon root=/dev/ram0 rdinit=/sbin/init")
    ap.add_argument("--kernel-addr", type=lambda x: int(x, 0), default=0x80080000)
    ap.add_argument("--ramdisk-addr", type=lambda x: int(x, 0), default=0x82000000)
    ap.add_argument("--second-addr", type=lambda x: int(x, 0), default=0x80F00000)
    ap.add_argument("--tags-addr", type=lambda x: int(x, 0), default=0x81E00000)
    ap.add_argument("--name", default="SP970")
    ap.add_argument("--partition-bytes", type=int, default=16 * 1024 * 1024)
    args = ap.parse_args()
    kernel = args.kernel.read_bytes()
    ramdisk = args.ramdisk.read_bytes() if args.ramdisk else b""
    dtb = args.dtb.read_bytes()
    if args.dtb_mode == "append-kernel":
        kernel = kernel + dtb
        dt_section = b""
        header_dt_size = 0
    elif args.dtb_mode == "qcdt-v2":
        dt_section = make_sp970_qcdt_v2(dtb)
        header_dt_size = len(dt_section)
    else:
        dt_section = dtb
        header_dt_size = len(dtb)
    if len(args.cmdline.encode()) > 512:
        raise SystemExit("cmdline exceeds Android v0 512-byte field")
    if len(args.name.encode()) > 15:
        raise SystemExit("name exceeds Android v0 15-byte payload")
    # Android boot header v0, as used by the captured factory boot.bin.
    magic = b"ANDROID!"
    header = struct.pack(
        "<8s10I16s512s8I1024s",
        magic,
        len(kernel), args.kernel_addr,
        len(ramdisk), args.ramdisk_addr,
        0, args.second_addr,
        args.tags_addr,
        PAGE,
        header_dt_size,
        0,
        args.name.encode().ljust(16, b"\0"),
        args.cmdline.encode().ljust(512, b"\0"),
        *struct.unpack("<8I", hashlib.sha1(kernel + ramdisk + dt_section).digest().ljust(32, b"\0")),
        b"\0" * 1024,
    )
    image = pad(header) + pad(kernel) + pad(ramdisk) + pad(dt_section)
    if len(image) > args.partition_bytes:
        raise SystemExit(f"image is {len(image)} bytes, over partition limit {args.partition_bytes}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    print(f"wrote {args.output} bytes={len(image)} sha256={hashlib.sha256(image).hexdigest().upper()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
