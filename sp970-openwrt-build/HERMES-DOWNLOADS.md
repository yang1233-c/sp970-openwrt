# HERMES download ledger

Policy: a required file or current-stage bundle below 1 GiB is fetched locally;
a larger finalized bundle is handed to Hermes with exact URLs, byte counts and
hashes.

## Current baseline completed locally

| URL | bytes | SHA-256 | state |
|---|---:|---|---|
| <https://github.com/openwrt/openwrt/archive/refs/tags/v25.12.5.tar.gz> | 11,564,496 | `19462C4D0D52824B33AE52F60EE5E66528BF103691AABDB5E1E15CC8924067DF` | downloaded; verified |
| <https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.94.tar.xz> | 148,301,108 | `E998A232B9418DB3301CB58468E291A4F41D6AB8306029B30D991F56251DC8D2` | downloaded; verified |

Current source pair: **159,865,604 bytes (152.46 MiB)**.
Fallback v25.12.4/6.12.87 cache: **159,793,472 bytes**, verified and retained.

## Pending measurement

The final OpenWrt `dl/` package set depends on `make defconfig` after the custom
MSM89xx target is integrated. Run `make download`, export its URL manifest and
sum the advertised sizes. If that finalized bundle reaches 1 GiB, create the
Hermes transfer manifest; otherwise fetch it locally. Moving feed branches must
first be pinned to commits.

No device or COM operation is part of this ledger.
