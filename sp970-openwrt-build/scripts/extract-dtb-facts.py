#!/usr/bin/env python3
"""Extract reproducible, board-relevant facts from an FDT/DTB.

This parser intentionally has no external dependency so it can run on a clean
Windows/Linux host.  It records values as strings, big-endian cells, or raw
hex; it never invents a pin or memory address.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

FDT_MAGIC = 0xD00DFEED
TOK_BEGIN_NODE = 1
TOK_END_NODE = 2
TOK_PROP = 3
TOK_NOP = 4
TOK_END = 9


def align4(value: int) -> int:
    return (value + 3) & ~3


def parse(path: Path) -> dict:
    blob = path.read_bytes()
    if len(blob) < 40:
        raise ValueError("DTB shorter than FDT header")
    header = struct.unpack(">10I", blob[:40])
    (magic, total, off_struct, off_strings, off_reserve, version, last_version,
     boot_cpuid, size_strings, size_struct) = header
    if magic != FDT_MAGIC:
        raise ValueError(f"bad FDT magic 0x{magic:08x}")
    if total > len(blob) or off_struct + size_struct > len(blob) or off_strings + size_strings > len(blob):
        raise ValueError("FDT offsets exceed file")
    strings = blob[off_strings:off_strings + size_strings]
    struct_blob = blob[off_struct:off_struct + size_struct]

    def string_at(offset: int) -> str:
        if offset >= len(strings):
            raise ValueError(f"string offset {offset} out of bounds")
        end = strings.find(b"\0", offset)
        if end < 0:
            raise ValueError("unterminated FDT string")
        return strings[offset:end].decode("utf-8", "replace")

    props: list[dict] = []
    nodes: list[str] = []
    stack: list[str] = []
    pos = 0
    while pos + 4 <= len(struct_blob):
        token = struct.unpack_from(">I", struct_blob, pos)[0]
        pos += 4
        if token == TOK_BEGIN_NODE:
            end = struct_blob.find(b"\0", pos)
            if end < 0:
                raise ValueError("unterminated node name")
            name = struct_blob[pos:end].decode("utf-8", "replace")
            pos = align4(end + 1)
            stack.append(name)
            nodes.append("/" + "/".join(x for x in stack if x))
        elif token == TOK_END_NODE:
            if not stack:
                raise ValueError("unbalanced FDT_END_NODE")
            stack.pop()
        elif token == TOK_PROP:
            if pos + 8 > len(struct_blob):
                raise ValueError("truncated FDT property header")
            length, name_offset = struct.unpack_from(">II", struct_blob, pos)
            pos += 8
            if pos + length > len(struct_blob):
                raise ValueError("truncated FDT property value")
            value = bytes(struct_blob[pos:pos + length])
            pos = align4(pos + length)
            props.append({
                "path": "/" + "/".join(x for x in stack if x),
                "name": string_at(name_offset),
                "value": value,
            })
        elif token == TOK_NOP:
            continue
        elif token == TOK_END:
            break
        else:
            raise ValueError(f"unknown FDT token {token} at {pos - 4}")

    by_path: dict[str, dict[str, bytes]] = {}
    for item in props:
        by_path.setdefault(item["path"], {})[item["name"]] = item["value"]

    def decode(value: bytes):
        if not value:
            return True
        if value.endswith(b"\0"):
            try:
                parts = value.rstrip(b"\0").split(b"\0")
                texts = [part.decode("utf-8") for part in parts]
                if all(all((ord(ch) >= 0x20 or ch in "\t\n\r") for ch in text) for text in texts):
                    return texts if len(texts) > 1 else texts[0]
            except UnicodeDecodeError:
                pass
        if len(value) % 4 == 0:
            return [f"0x{x:x}" for x in struct.unpack(">" + "I" * (len(value) // 4), value)]
        return {"hex": value.hex()}

    def property_value(path: str, name: str):
        value = by_path.get(path, {}).get(name)
        return None if value is None else decode(value)

    # Keep this list deliberately narrow: the output is for board bring-up,
    # not a copy of every kernel tuning table in a vendor DTB.
    interesting_names = {
        "compatible", "model", "status", "reg", "reg-names", "device_type",
        "stdout-path", "dr_mode", "phy_type", "phy-names", "phys", "extcon",
        "memory-region", "firmware", "interrupts", "interrupt-names", "clocks",
        "clock-names", "resets", "reset-names", "vmmc-supply", "vqmmc-supply",
        "mmc-ddr-1_8v", "non-removable", "cd-gpios", "wp-gpios", "gpios", "label",
        "linux,default-trigger", "remote-pid", "qcom,smem-states", "qcom,smem-state-names",
        "qcom,smd-edge", "qcom,smd-channels", "qcom,qrtr-node", "qcom,ipc",
        "qcom,local-pid", "qcom,client-id", "qcom,init-seq", "qcom,state", "qcom,state-names",
        "pinctrl-names", "pinctrl-0", "pinctrl-1", "pinctrl-2", "qcom,sd-lines",
    }
    selected_paths = []
    selected = []
    path_needles = ("sdhci", "usb@", "remoteproc", "wwan", "wcnss", "wifi", "smd",
                    "gpio-keys", "leds", "serial@", "pinctrl", "memory@", "reserved-memory",
                    "chosen", "aliases", "cpus/cpu@", "firmware/scm")
    for path_name in sorted(by_path):
        if path_name in ("/",):
            include = True
        else:
            include = any(needle in path_name for needle in path_needles)
        if not include:
            continue
        selected_paths.append(path_name)
        values = {
            name: decode(value)
            for name, value in sorted(by_path[path_name].items())
            if name in interesting_names
        }
        if values:
            selected.append({"path": path_name, "properties": values})

    root = by_path.get("/", {})
    result = {
        "source": str(path),
        "sha256": hashlib.sha256(blob).hexdigest().upper(),
        "bytes": len(blob),
        "fdt": {
            "total_size": total,
            "version": version,
            "last_compatible_version": last_version,
            "boot_cpuid_phys": f"0x{boot_cpuid:x}",
            "node_count": len(nodes),
            "property_count": len(props),
        },
        "root": {
            "model": decode(root["model"]) if "model" in root else None,
            "compatible": decode(root["compatible"]) if "compatible" in root else None,
        },
        "selected_nodes": selected,
        "notes": [
            "Values are decoded directly from the supplied DTB; absent values remain absent.",
            "The DTB memory node is recorded as-is and must not be replaced by a guessed RAM map.",
        ],
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dtb", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()
    result = parse(args.dtb)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({len(result['selected_nodes'])} selected nodes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

