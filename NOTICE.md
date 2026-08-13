# Notices and provenance

This project integrates or adapts material from:

- [OpenWrt](https://openwrt.org/) — build system, configuration conventions,
  init scripts and mac80211 packaging; GPL-2.0 and component-specific licenses.
- [Linux](https://kernel.org/) — MSM8916 device-tree and kernel interfaces;
  the included SP970 DTS declares `GPL-2.0-only`.
- [libqmi](https://gitlab.freedesktop.org/mobile-broadband/libqmi) and
  [libqrtr-glib](https://gitlab.freedesktop.org/mobile-broadband/libqrtr-glib)
  — runtime APIs used by the `q410qmi` tools; upstream LGPL licensing applies
  to those libraries.

- [qrtr](https://github.com/linux-msm/qrtr),
  [rmtfs](https://github.com/andersson/rmtfs) and
  [tqftpserv](https://github.com/linux-msm/tqftpserv) — pinned source snapshots
  used to build the modem file-service daemons; BSD-3-Clause licensing applies.

Captured factory images, Qualcomm firmware, device dumps and third-party
download archives are not distributed by this repository. Their hashes may be
documented solely to identify local build inputs.

Copyright in third-party files remains with the respective authors. Project-
authored additions are Copyright (C) 2026 peterhon168 and licensed under
GPL-2.0-only.
