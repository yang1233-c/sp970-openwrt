# Public release security audit

Audit date: 2026-08-13

## Publication model

The public `main` branch is created as a new root commit. The private engineering
history is not an ancestor and is not pushed.

## Excluded

- SSH identity and known-host paths.
- Device eMMC CID, fastboot serial and other unique identifiers.
- SIM identifiers and raw UIM/NAS reports.
- Neighbouring Wi-Fi SSIDs/BSSIDs and packet/RF captures.
- Windows usernames, personal absolute paths and private host inventories.
- Factory dumps, QCN containers, modem NV content, preimages, firmware and
  generated images.
- Experimental logs, terminal transcripts and cached third-party webpages.
- Unstripped ARM64 binaries containing compiler build paths.

## Automated gates

The exported tree is scanned for private-key markers, common provider-token
formats, authorization headers, credential assignments, long decimal device/SIM
identifiers, private key filenames, personal path fragments and known reference
device identifiers. Binary files and files larger than the repository policy
are enumerated separately.

The public release contains source for both `q410qmi` executables and an OpenWrt
package definition so the omitted binaries can be rebuilt from the pinned tree.
QCN work is represented only by a redacted field map, container byte count and
donor SHA-256; current-device identities, calibration payloads and rollback
preimages remain in the private artifact archive.
