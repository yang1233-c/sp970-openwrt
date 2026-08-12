# Source lock (A / SP970_MB_V02)

All checksums below are SHA-256, uppercase. A URL is pinned to an immutable
release/tag where the upstream project provides one. The OpenWrt tag was
resolved and dereferenced with local Git on 2026-08-10.

| component | URL | pinned revision/version | bytes | SHA-256 | state |
|---|---|---:|---:|---|---|
| **current** OpenWrt build system | <https://github.com/openwrt/openwrt/archive/refs/tags/v25.12.5.tar.gz> | v25.12.5 / commit `f0a60eee2fe051741c643ea6118718aae1ef17fb` / tag object `e20bc3ec9eb9e3dbd0519ddc18f81f3eedc0f45e` | 11,564,496 | `19462C4D0D52824B33AE52F60EE5E66528BF103691AABDB5E1E15CC8924067DF` | downloaded; verified |
| **current** Linux kernel source | <https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.94.tar.xz> | 6.12.94 (OpenWrt 25.12.5 generic line) | 148,301,108 | `E998A232B9418DB3301CB58468E291A4F41D6AB8306029B30D991F56251DC8D2` | downloaded; verified |
| Linux source hash in OpenWrt | <https://raw.githubusercontent.com/openwrt/openwrt/v25.12.5/target/linux/generic/kernel-6.12> | `LINUX_VERSION-6.12=.94` | n/a | `e998a232b9418db3301cb58468e291a4f41d6ab8306029b30d991f56251dc8d2` | cross-checked |
| fallback OpenWrt cache | <https://github.com/openwrt/openwrt/archive/refs/tags/v25.12.4.tar.gz> | v25.12.4 / `db273801a24e9367b4f989febc469888a2343e31` | 11,527,644 | `FD8B78EC4675C8B19831EBF0299335F5C65CAA60E34655490A8979720633EE2D` | downloaded; fallback only |
| fallback Linux cache | <https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.87.tar.xz> | 6.12.87 | 148,265,828 | `CC12A7644B4CEF9E06627B29DE8753E22B3D076703A9B52BE84263E05C8B9830` | downloaded; fallback only |

The local board inputs are intentionally not network dependencies. Their
observed hashes are recorded here so a later port can prove it used the same
facts:

| input | bytes | SHA-256 |
|---|---:|---|
| local reference `dtb-00506762.dtb` | 46,789 | `35BB2D3648D8C26F3379C5CCC05CCCE3E021C36150102C9815B2BACDA45A4D42` |
| local reference `SP970-OpenWrt-2023-rootfs.raw` | 1,073,741,824 | `A348D87F16630C3674E69D38064A0453F0958B81C6DA2249823B5067C4ACB171` |
| local factory `partitions/gpt-partitions.json` | 8,978 | `07FA898D470888E0D513BF20DAA99F7D90C69E6CC3292CF9A7D776426A2D6579` |
| factory `partitions\boot.bin` | 16,777,216 | `C5F8A0B2DAB3B6FBBF517B64C52FCC742312F101F27142083123D319256A6B05` |
| legacy `SP970\boot.img` | 5,319,509 | `6F100C41D1267EFBD2145BB379B6DA9970DFA34C042DF98E0A918DA83C3CC595` |

## Feeds

The successful initramfs build used the release-pinned `feeds.conf.default`
from the v25.12.5 tree:

| feed | pinned commit |
|---|---|
| packages | `5caa62e0bc9f7fb9b0c12a23267bceb7724214dd` |
| luci | `128a7812f4be233c5dd7f7466f534fd888785caf` |
| routing | `3d7d0dc7fa43d3eb09498417407e95a6552e5312` |
| telephony | `2618106d5846a4a542fdf5809f0d3ed228ce439b` |
| video | `094bf58da6682f895255a35a84349a79dab4bf95` |

Additional build inputs fetched by OpenWrt and verified locally:

| input | bytes | SHA-256 |
|---|---:|---|
| `backports-6.18.26.tar.zst` | 12,257,871 | `2AD578C6CAE22F192FEFD44E1449725228D4109EE781998B41DCBAE872554968` |
| `openssl-3.5.7.tar.gz` | 53,153,930 | `A8C0D28A529CA480F9F36CF5792E2CD21984552A3C8E4AA11A24AA31AEAC98E8` |
