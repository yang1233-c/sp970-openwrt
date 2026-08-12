# Rollback model

The private reference deployment retains three rollback layers:

1. Exact preimages for the persistent boot and rootfs write ranges.
2. A cellular-integration preimage restoring network, modem and LED files.
3. A complete factory boot-chain image set with per-file hashes.

Those device-specific payloads are excluded from the public repository.

Before a persistent deployment:

1. Read and hash the target GPT and every partition range that will be written.
2. Confirm the preimage sizes and store copies on a different physical disk.
3. Hash every payload immediately before writing.
4. Read the written range back and compare it byte-for-byte with the payload.
5. Keep a tested fastboot/EDL entry route and a one-command restore manifest.
6. Do not alter modem NV partitions for the `q410qmi` integration; use a
   file-backed RMTFS shadow when evaluating modem state changes.

The included deployment tools use expected hashes and explicit target paths.
Replace their typed local asset paths only after validating the exact board and
partition layout.
