# SP970 OpenWrt build tree

This directory contains the OpenWrt 25.12.5 board port, rootfs overlay and
local package definitions for the SP970/MSM8916 target.

## Included

- MSM8916 target, kernel configuration and SP970 device tree.
- Wi-Fi AP, DHCP/NAT and USB NCM management overlay.
- `q410qmi`, a source-built single-owner QMI data path for the onboard modem.
- LED policy: red heartbeat, green AP-ready and blue cellular-connected.
- Local firmware packaging hooks. Captured modem/WLAN firmware is deliberately
  excluded from Git.

## Source baseline

- OpenWrt v25.12.5, commit `f0a60eee2fe051741c643ea6118718aae1ef17fb`.
- Linux 6.12.94.
- Full source locks and hashes are recorded in [`SOURCE-LOCK.md`](SOURCE-LOCK.md).

## Build

```powershell
Set-Location .\sp970-openwrt-build
.\scripts\download-sources.ps1 -Extract
.\scripts\lint.ps1
.\scripts\build.ps1 -SourceDir .work\openwrt
```

For WSL packaging, set the Linux OpenWrt path when it differs from the default:

```powershell
$env:Q410_OPENWRT_TREE = '/home/<user>/q410/openwrt-25.12.5'
.\scripts\package-initramfs-from-wsl.ps1
```

Local firmware is expected outside the repository under a path selected by
`SP970_FIRMWARE_DIR`. The repository contains hashes and packaging logic, not
captured binary firmware or factory images.

## Cellular implementation

The persistent profile builds `package/network/utils/q410qmi` from source. On
the tested slot-1 USIM it activates the Primary GW application, waits for LTE
packet-service registration, negotiates QMI Raw-IP/no-QoS and publishes the
address, default route and carrier DNS through netifd. A supervisor maintains
exactly one long-lived WDS client.

## Hardware validation

The tested persistent candidate completed autonomous boot, Wi-Fi AP startup and
cellular data setup. Public evidence is summarized at
[`../docs/STATUS.md`](../docs/STATUS.md). Device-specific raw dumps, identifiers,
neighbouring BSSIDs and local paths are excluded from the public release.

Persistent installation changes device partitions. Preserve verified preimages
and readback hashes before deployment; see [`../docs/ROLLBACK.md`](../docs/ROLLBACK.md).
