# Public project status

## Validated on the reference SP970

- Persistent OpenStick-compatible early boot chain.
- Persistent OpenWrt boot and ext4 rootfs.
- USB NCM management at a link-local address.
- `SP970-CAR` 2.4 GHz AP with one hostapd and one netifd instance.
- Slot-1 USIM Primary GW activation and LTE packet-service registration.
- Raw-IP/no-QoS WDS session managed by one long-lived QMI owner.
- USIM AID discovery and carrier APN selection without recording the full IMSI.
- IPv4 address, default route and carrier DNS published through netifd.
- Public IPv4 ping and HTTP connectivity checks passed.
- CPUFreq registered through `cpufreq-dt`; the validated policy reaches 998.4 MHz.
- Software flow offload enabled for routed client traffic.
- `rmtfs` and `tqftpserv` are built from pinned source snapshots by the local
  `qcom-modem-daemons` OpenWrt package.
- LED policy: red heartbeat, green AP-ready, blue cellular-connected.
- Physical modem-NV partition hashes unchanged across the integration work.

One post-fix reboot observation reached automatic cellular network availability
in about 28 seconds and registered on PLMN 46015, LTE B3, EARFCN 1300. This is
evidence of functionality, not a statistical production
qualification.

## Remaining release gates

- 20 successful physical ignition/power cycles.
- 72-hour continuous operation and sudden-power-loss recovery.
- End-to-end Wi-Fi client NAT validation.
- Investigate the observed short-sample cellular packet loss while preserving a
  single QMI owner.
- Vehicle head-unit association, DHCP and usable network within 30 seconds.
- Passive RF measurement of the first real beacon; bridge forwarding remains a
  diagnostic rather than a beacon measurement.

The second UFI003-based stick remains a separate recovery project and is not
part of this public SP970 release.
