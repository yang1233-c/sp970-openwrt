# SP970 QCN policy and public redaction record

## What stays outside Git

QCN is a device-level NV/EFS container, not a portable band-unlock patch. A
full image may contain IMEI/MEID/ESN, SIM provisioning state, RF/TCXO
calibration, PDP profiles and board-specific RFNV. The repository therefore
excludes `*.qcn`, modemst/fsg/fsc payloads, full eMMC images and rollback
preimages.

The private backup set retains byte counts and SHA-256 checksums. The public
tree records only a donor identity hash and a redacted field-level policy.

## Audited donor

- container size: 570,880 bytes
- SHA-256: `FD06D09D7D358C2956D4FDB8F802DFEFB381E53982AF3BE296AF1BA5C8E2A1BB`
- declared source family: different from the reference SP970 firmware family
- whole-image restore policy: excluded

## Field-level policy evaluated on the reference fixture

Only these policy fields were considered; device identity, UIM, RFNV and
calibration records were excluded:

| field | redacted public value | interpretation |
|---|---|---|
| NV6828 | `0x000001E000000095` | LTE B1/B3/B5/B8/B38/B39/B40/B41 preference mask |
| NV6829 | `0x0` | no additional LTE mask bits |
| `update_band_range` | `01 00 29 00 50 A0 18 A1 00 00 00 00 00 00 00 00 00 00 00` | donor policy blob |
| `band_priority_list` | `03 01 05` | B3, B1, B5 priority |
| `policyman/rat_mask` | LTE portion matches the mask above | RAT policy only; identity bytes excluded |

A mask bit is not proof of usable RF hardware. MPSS support, PDC/MBN policy,
PA/FEM/filter/duplexer population and per-board calibration still determine
whether a band can transmit, receive and register.

## Reversible workflow

1. Capture a consistent preimage QCN and hash it before any policy write.
2. Read the live target fields and compare type, length and path.
3. Write only the explicit whitelist above.
4. Read every written field back immediately.
5. Cold boot, re-read, and verify normal SIM, PLMN, serving band and data state.
6. Keep a tested restore path to the preimage and verify rollback across boot.

The final fixture registered on PLMN 46015 and served LTE B3 / EARFCN 1300.
That validates B3 operation only; it does not prove every masked band.
