#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -u

echo 'Q410_QMI_POLLERS_BEFORE'
ps w | grep -E 'sp970-(modem-led|led-state)|rmtfs|tqftp' | grep -v grep || true

# Runtime-only procd changes: init enablement and on-disk service definitions stay intact.
ubus call service delete '{"name":"sp970-led-state"}' 2>/dev/null || true
ubus call service delete '{"name":"sp970-modem","instance":"led"}' 2>/dev/null || true
sleep 2

echo 'Q410_QMI_POLLERS_AFTER'
ps w | grep -E 'sp970-(modem-led|led-state)|rmtfs|tqftp' | grep -v grep || true

if ps w | grep -E 'sp970-(modem-led|led-state)' | grep -v grep >/dev/null; then
	echo 'Q410_QMI_POLLERS_QUIESCE_FAILED'
	exit 1
fi
if ! ps w | grep '/usr/sbin/rmtfs' | grep -v grep >/dev/null; then
	echo 'Q410_RMTFS_MISSING'
	exit 2
fi

echo 'Q410_QMI_POLLERS_QUIESCED rmtfs=running'
