# Q410 artifact manifests

Large firmware images, device dumps, source caches, build outputs and external
backup trees stay out of Git. The JSON and SHA-256 index identify immutable
NCM16/NCM19 artifacts by workspace path, byte count and content hash.

The indexes are split by payload location:

- `q410-ncm-baselines.json` and `q410-ncm-baselines.sha256` identify the four
  local NCM16/NCM19 boot-image/kernel-initramfs artifacts and the two runtime
  baselines.
- `q410-external-assets.json` records the same four image identities, every
  archive in `sp970-openwrt-build/source-cache`, external source packages,
  the A/B factory authority indexes and payload identities, the Stage14
  rollback preimages, and a complete metadata inventory of the external backup
  tree.
- `q410-qcn-redacted-assets.json` records only the reviewed donor container
  byte count/hash and the field-level LTE policy. QCN/NV payloads and current
  device rollback material remain outside Git.

No image, source archive or J: backup payload is copied into `manifests/`.

## Content identity versus metadata snapshots

`ContentVerified=true` always means the listed byte count is paired with a
file-content SHA-256. The four-file source cache additionally has a deterministic
content-tree identity: records are sorted by ordinal relative path and encoded
as `SHA256<TAB>BYTES<TAB>RELATIVE_PATH<LF>` in UTF-8 without BOM. Its frozen
identity is 4 files, 319,659,076 bytes, tree SHA-256
`4D1B0207D3E40901DC59ABF0A88120056C736586A59A901DC4D2915822F69C1A`.

The 17,957,893,187-byte external backup tree is deliberately not rehashed in full.
All 25 top-level directories (918 files total) instead carry
`IdentityKind=metadata_snapshot_path_size_sha256` and
`ContentVerified=false`. That digest is a deterministic inventory of
`BYTES<TAB>RELATIVE_PATH<LF>`, not a content claim. The aggregate inventory
SHA-256 is
`BE509930D88B49FFB5FE945EBEB564357F09EA9F48C27DF097FCDAC77AD16369`.
Content claims are separately anchored by direct hashes of A/B `manifest.json`
and `SHA256SUMS.csv`, the factory payload rows in those indexes, and direct
hashes of all seven current Stage14 rollback preimages. In particular,
`preimage-boot-head.bin` remains 32,768 bytes with SHA-256
`2D89024DD4D91F98038E3E6FE5D7FCD37E826AA5FA62A67045D301995B6B4FDC`.

## Verification

Offline/workspace verification checks all local images, baseline snapshots,
source-cache file contents and external-manifest relationships:

```powershell
.\tools\New-Q410-ArtifactManifest.ps1 -VerifyOnly
```

When the external backup volume is mounted, add `-VerifyExternal`. This
recomputes direct external
source/index/preimage hashes, validates the four large factory payload records
against the content-verified `SHA256SUMS.csv` files without rereading all
17.96 GB, and recomputes every path/size metadata inventory:

```powershell
.\tools\New-Q410-ArtifactManifest.ps1 -VerifyOnly -VerifyExternal
```

`NCM19` was the working overlay at freeze time. `NCM16` has exact recovery for
the selected runtime files extracted from its built-in initramfs; its complete
uncommitted host build-tree state has partial recovery confidence.

## Selected derived candidate

`q410-ncm19-led1.json` records the selected persistent NCM19-LED1 image, its exact gpio-leds module, the installed 64 MiB boot readback, and the immediate NCM19 rollback image. The original NCM16/NCM19 baseline records remain immutable.
