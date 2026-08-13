#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

[ -x /usr/sbin/q410-qmi-uim-provision ] || exit 0
[ -x /usr/sbin/q410-qmi-wds-connect ] || exit 0
[ -x /usr/sbin/q410-wds-supervisor ] || exit 0
[ -x /usr/sbin/q410-sim-profile ] || exit 0
[ -x /usr/bin/qmicli ] || exit 0

. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

Q410_WDS_STATE=/tmp/q410-wds-ready.env
Q410_LED_STATE=/run/sp970-cellular-state

q410qmi_write_led_state() {
	local state="$1"
	local sim="$2"
	local reason="${3:-none}"
	local tmp="${Q410_LED_STATE}.$$"

	{
		printf 'STATE=%s\n' "$state"
		printf 'SIM=%s\n' "$sim"
		printf 'REASON=%s\n' "$reason"
	} >"$tmp" && mv "$tmp" "$Q410_LED_STATE"
}

proto_q410qmi_init_config() {
	available=1
	proto_config_add_string qmi_device
	proto_config_add_string data_device
	proto_config_add_string apn
	proto_config_add_string aid
	proto_config_add_int metric
	proto_config_add_defaults
}

q410qmi_fail() {
	local interface="$1"
	local reason="$2"
	local led_state=searching
	local sim_state=unknown

	case "$reason" in
		QMI_DEVICE_MISSING|DMS_ONLINE_FAILED)
			led_state=modem_absent
			;;
		SIM_*|UIM_*)
			led_state=sim_absent
			sim_state=absent
			;;
		APN_*|WDS_*)
			led_state=registered_no_data
			sim_state=present
			;;
	esac
	q410qmi_write_led_state "$led_state" "$sim_state" "$reason"
	logger -t q410qmi "${interface}: ${reason}"
	proto_notify_error "$interface" "$reason"
	case "$reason" in
		UIM_*|SIM_*|APN_*) proto_block_restart "$interface" ;;
	esac
	proto_kill_command "$interface" 15
	rm -f "$Q410_WDS_STATE"
	return 1
}

proto_q410qmi_setup() {
	local interface="$1"
	local netifd_device="$2"
	local device qmi_device data_device apn aid metric
	local i mode_output nas_output dms_ready registered

	json_get_vars qmi_device data_device apn aid metric
	device="${qmi_device:-/dev/wwan0qmi0}"
	data_device="${data_device:-${netifd_device:-wwan0}}"
	apn="${apn:-auto}"
	aid="${aid:-auto}"
	metric="${metric:-10}"

	i=0
	while { [ ! -c "$device" ] || [ ! -e "/sys/class/net/$data_device" ]; } && \
			[ "$i" -lt 30 ]; do
		sleep 1
		i=$((i + 1))
	done
	[ -c "$device" ] || {
		q410qmi_fail "$interface" QMI_DEVICE_MISSING
		return
	}
	[ -e "/sys/class/net/$data_device" ] || {
		q410qmi_fail "$interface" DATA_DEVICE_MISSING
		return
	}

	rm -f "$Q410_WDS_STATE"
	q410qmi_write_led_state initializing unknown SETUP
	ip addr flush dev "$data_device"
	ip link set "$data_device" up || {
		q410qmi_fail "$interface" DATA_DEVICE_OPEN_FAILED
		return
	}

	# This MPSS cold-boots in "shutting-down" mode.  Bring it online once,
	# before UIM/WDS ownership is handed to the long-lived single QMI client.
	dms_ready=0
	i=0
	while [ "$i" -lt 30 ]; do
		mode_output="$(qmicli -d "$device" --dms-get-operating-mode 2>&1 || true)"
		case "$mode_output" in
			*"Mode: 'online'"*) dms_ready=1; break ;;
			*) qmicli -d "$device" --dms-set-operating-mode=online >/dev/null 2>&1 || true ;;
		esac
		sleep 2
		i=$((i + 2))
	done
	[ "$dms_ready" -eq 1 ] || {
		q410qmi_fail "$interface" DMS_ONLINE_FAILED
		return
	}

	if [ "$aid" = auto ]; then
		aid="$(/usr/sbin/q410-sim-profile aid "$device")" || {
			q410qmi_fail "$interface" SIM_AID_DETECT_FAILED
			return
		}
		logger -t q410qmi "${interface}: detected USIM AID"
	fi
	q410qmi_write_led_state searching present NAS_SEARCH

	registered=0
	i=0
	while [ "$i" -lt 45 ]; do
		if [ "$i" -eq 0 ] || [ "$i" -eq 16 ]; then
			/usr/sbin/q410-qmi-uim-provision "$device" activate 1 "$aid" || {
				q410qmi_fail "$interface" UIM_PROVISION_FAILED
				return
			}
		fi
		nas_output="$(qmicli -d "$device" --nas-get-serving-system 2>&1 || true)"
		if printf '%s\n' "$nas_output" | grep -Fq "Registration state: 'registered'" &&
				printf '%s\n' "$nas_output" | grep -Fq "PS: 'attached'"; then
			registered=1
			break
		fi
		sleep 2
		i=$((i + 2))
	done
	[ "$registered" -eq 1 ] || {
		q410qmi_fail "$interface" NAS_REGISTRATION_TIMEOUT
		return
	}
	q410qmi_write_led_state registered_no_data present PS_ATTACHED

	if [ "$apn" = auto ]; then
		apn="$(/usr/sbin/q410-sim-profile apn "$device")" || {
			q410qmi_fail "$interface" APN_DETECT_FAILED
			return
		}
		logger -t q410qmi "${interface}: selected APN ${apn} from IMSI"
	fi

	proto_run_command "$interface" \
		/usr/sbin/q410-wds-supervisor "$device" "$apn"

	i=0
	while [ "$i" -lt 45 ]; do
		[ -s "$Q410_WDS_STATE" ] && break
		sleep 1
		i=$((i + 1))
	done
	[ -s "$Q410_WDS_STATE" ] || {
		q410qmi_fail "$interface" WDS_CONNECT_TIMEOUT
		return
	}

	. "$Q410_WDS_STATE"
	[ "${STATE:-}" = connected ] || {
		q410qmi_fail "$interface" WDS_STATE_INVALID
		return
	}
	[ "${IFACE:-}" = "$data_device" ] || {
		q410qmi_fail "$interface" WDS_DATA_DEVICE_MISMATCH
		return
	}

	[ -n "${MTU:-}" ] && ip link set dev "$data_device" mtu "$MTU"

	proto_init_update "$data_device" 1
	proto_set_keep 1
	proto_add_ipv4_address "$IPV4" "$NETMASK"
	proto_add_ipv4_route 0.0.0.0 0 "$GATEWAY" "$IPV4" "$metric"
	[ -n "${DNS1:-}" ] && proto_add_dns_server "$DNS1"
	[ -n "${DNS2:-}" ] && proto_add_dns_server "$DNS2"
	proto_send_update "$interface"

	{
		echo 'STATE=connected'
		echo 'SIM=present'
		echo 'REASON=WDS_CONNECTED'
		echo "IFACE=$data_device"
		echo "APN=$apn"
		echo "IPV4=$IPV4"
		echo "DNS1=${DNS1:-}"
		echo "DNS2=${DNS2:-}"
	} >"$Q410_LED_STATE"
	logger -t q410qmi "${interface}: connected via ${data_device}, IPv4 ${IPV4}"
}

proto_q410qmi_teardown() {
	local interface="$1"
	proto_kill_command "$interface" 15
	rm -f "$Q410_WDS_STATE"
	q410qmi_write_led_state modem_absent unknown TEARDOWN
}

add_protocol q410qmi
