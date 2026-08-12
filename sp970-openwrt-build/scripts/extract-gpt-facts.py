#!/usr/bin/env python3
"""Condense the captured GPT manifest without altering the source image."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("-o", "--output", type=Path, required=True)
    args = ap.parse_args()
    raw = args.manifest.read_bytes()
    data = json.loads(raw)
    wanted = {"boot", "system", "persist", "cache", "recovery", "userdata"}
    parts = []
    for item in data.get("partitions", []):
        if item.get("name") in wanted:
            parts.append({
                "index": item["index"],
                "name": item["name"],
                "partuuid": item["uniqueGuid"].lower(),
                "first_lba": item["firstLba"],
                "last_lba": item["lastLba"],
                "offset_bytes": item["offset"],
                "length_bytes": item["length"],
                "attributes": item["attributes"],
            })
    out = {
        "source": str(args.manifest),
        "source_sha256": hashlib.sha256(raw).hexdigest().upper(),
        "source_length": data.get("sourceLength"),
        "sector_size": data.get("sectorSize"),
        "disk_guid": data.get("diskGuid"),
        "first_usable_lba": data.get("firstUsableLba"),
        "last_usable_lba": data.get("lastUsableLba"),
        "partitions": parts,
        "cmdline_profiles": {
            "system_root": "root=PARTUUID=221d96c0-58b2-7008-8810-332c39e879df rootwait rw",
            "userdata_overlay": "overlayfs:/dev/disk/by-partuuid/2200ec70-9c9d-f4ce-5b2a-b462675c347a",
        },
        "notes": [
            "PARTUUID and byte ranges are copied from gpt-partitions.json; no GPT rewrite is implied.",
            "The system-root profile is a plan for a preserved-GPT validation boot; verify the kernel rootfs format before writing any partition.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({len(parts)} partitions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

