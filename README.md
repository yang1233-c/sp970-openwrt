# q410-sp970-openwrt

OpenWrt adaptation for the Qualcomm MSM8916-based SP970: persistent boot,
2.4 GHz access point, USB NCM management, single-owner QMI cellular data,
three-colour LED state and verified rollback tooling.

## Repository scope

- [`sp970-openwrt-build/`](sp970-openwrt-build/) ? OpenWrt target, device tree,
  configuration, rootfs overlay and source-built `q410qmi` package.
- [`tools/`](tools/) ? selected build, deployment and cellular integration
  sources/scripts.
- [`baselines/`](baselines/) ? source overlays recovered from immutable NCM16
  and NCM19 comparison images; the images themselves are excluded.
- [`docs/STATUS.md`](docs/STATUS.md) ? current validated result and remaining
  release gates.
- [`docs/ROLLBACK.md`](docs/ROLLBACK.md) ? rollback model and required checks.

## Current result

The tested persistent candidate boots from eMMC, starts `SP970-CAR`, activates
a slot-1 USIM and establishes a Raw-IP QMI data session automatically. The
fixed kernel registers CPUFreq, routed traffic uses software flow offload, and
`rmtfs`/`tqftpserv` are rebuilt from pinned source. A post-fix reboot reached
cellular availability in approximately 28 seconds on PLMN 46015, LTE B3,
EARFCN 1300. Physical modem-NV partition hashes remained unchanged.

This is an engineering port rather than a universal image. Board revisions,
partition maps and firmware provenance must be verified independently.

## Build inputs

The repository intentionally excludes:

- factory/partition dumps, QCN containers and rollback preimages;
- captured WCNSS/MPSS firmware;
- boot/rootfs images and archives;
- SIM identifiers, device serials and raw RF scan results;
- local credentials, host paths and private test logs.

See [`sp970-openwrt-build/SOURCE-LOCK.md`](sp970-openwrt-build/SOURCE-LOCK.md)
for the pinned upstream source versions. Supply locally obtained firmware using
`SP970_FIRMWARE_DIR`.

## License

Project-authored code is released under GPL-2.0-only. Files derived from Linux,
OpenWrt or other upstream projects retain their upstream licensing and notices.
See [`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md).
