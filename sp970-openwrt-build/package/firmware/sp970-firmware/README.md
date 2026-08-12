# Local firmware input

Populate a private directory (for example `local-firmware/sp970/`) with the
owner-extracted `modem.*`, `mba.mbn`, `wcnss.*` and any board-specific files
required by the selected kernel. The scaffold package copies files from
`SP970_FIRMWARE_DIR` only; it does not download, encode, or publish proprietary
firmware. Record filenames and SHA-256 in the consuming build's report before
building.

For WCN36xx, preserve the relative path
`wlan/prima/WCNSS_qcom_wlan_nv.bin`. The current A capture also supplies
`wlan/prima/WCNSS_cfg.dat`; the kernel driver directly requests the NV file.
