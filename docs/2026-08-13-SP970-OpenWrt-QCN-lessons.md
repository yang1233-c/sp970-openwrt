# SP970 OpenWrt, QCN and modem bring-up lessons

## Confirmed root causes and fixes

### CPUFreq deferred forever without the A53 PLL

`CONFIG_QCOM_CLK_APCS_MSM8916=y` alone was insufficient. APCS uses the A53 PLL
as a parent, so omitting `CONFIG_QCOM_A53PLL` left APCS and `cpufreq-dt` in
deferred probe. The fixed kernel registers `cpufreq-dt` and exposes a maximum
frequency of 998400 kHz.

### Flow offload affects forwarding, not local downloads

Software flow offload helps established LAN/USB-to-cellular forwarding flows.
It does not accelerate a download initiated by the router itself. Keep
hardware flow offload disabled on this target.

### A working init script does not prove its executables were packaged

The persistent rootfs contained `sp970-modem` and `sp970-rmtfs-start`, but
omitted `/usr/sbin/rmtfs` and `/usr/bin/tqftpserv`. MPSS stayed offline, so no
WWAN/QMI ports appeared. Both daemons are now built by the pinned
`qcom-modem-daemons` source package, and lint requires that package in the
persistent seed.

### A watchdog was mistaken for a one-shot shutdown helper

`stop_service()` invoked `sp970-modem-led off`, but that program waits for QMI
and loops forever. Service stop and software reboot consequently hung. procd
already owns the rmtfs/tqftp instances; the corrected stop hook simply returns.

### New Windows scp defaults to SFTP

The minimal OpenWrt image has no `sftp-server`. Windows OpenSSH `scp` therefore
needs `-O` to select the legacy SCP protocol for recovery transfers.

### PowerShell-to-SSH pipelines can inject a UTF-8 BOM

Piping a here-string from Windows PowerShell 5.1 to remote `sh -s` introduced a
BOM and produced `sh: set: not found`. Passing the script as the SSH command
argument, or writing explicit BOM-free bytes, avoids that false failure.

### BusyBox utilities differ from full distributions

This image lacked `timeout`, and its `ip` did not support every iproute2
shortcut. Bounded probes use background PIDs plus `kill -0`; mount checks use
`/proc/mounts` instead of assuming `findmnt` output names the physical root
partition.

### QMI control is a single-owner resource on this MPSS

Parallel `qmicli` probes can produce CID allocation failures, endpoint hangups
or indefinite waits while the WDS supervisor owns the endpoint. Use the AT
control port for independent read-only status when possible. If a QMI query is
required, serialize it and enforce a bounded process timeout.

### SIM insertion requires modem enumeration, not a QCN rewrite

After rmtfs/tqftp were restored, MPSS reached `running`, the WWAN control ports
appeared, the USIM AID was detected, APN `cbnet` was selected from the IMSI and
the data session came up automatically. A software reboot repeated the path in
about 28 seconds while the modem NV partition hashes remained unchanged.

## Validation gates that caught real faults

- exact artifact size and SHA-256 before every write;
- post-write partition readback;
- root filesystem and boot command-line checks after reboot;
- CPUFreq driver and maximum frequency checks;
- RMTFS partition-label mapping checks;
- one daemon instance each for rmtfs and tqftpserv;
- SIM ready, numeric PLMN, RAT, serving band/EARFCN and PDP/APN checks;
- a second software reboot to prove persistence;
- clean `e2fsck` plus file extraction/hash verification for patched ext4 images.

## Performance interpretation

The final fixture reached PLMN 46015 on LTE B3 / EARFCN 1300 with healthy
instantaneous signal values, but short public ping samples still showed high
loss. Treat public endpoint, cell load, antenna placement and BAM-DMUX/WDS data
path behaviour as separate variables. Do not attribute every throughput gap to
the distribution name or the LTE mask.
