#!/bin/sh
set -eu

workspace="${1:-$(cd "$(dirname "$0")/.." && pwd -P)}"
helper="$workspace/sp970-openwrt-build/files/usr/sbin/q410-sim-profile"
tmp="${TMPDIR:-/tmp}/q410-sim-profile-test-$$"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp"

cat >"$tmp/qmicli" <<'EOF'
#!/bin/sh
case "$*" in
  *--uim-get-card-status*)
    cat <<'CARD'
Slot [1]:
  Card state: 'present'
  Application [1]:
    Application type:  'usim (2)'
    Application state: 'ready'
    Application ID:
      A0:BC:00:DE:01:02:FA:04
CARD
    ;;
  *--dms-uim-get-imsi*)
    printf "IMSI: '%s'\n" "${TEST_IMSI:?}"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp/qmicli"

aid="$(QMICLI="$tmp/qmicli" sh "$helper" aid /dev/fixture)"
[ "$aid" = A0BC00DE0102FA04 ]

for row in \
  '460150 cbnet' \
  '460110 ctnet' \
  '460010 3gnet' \
  '460070 cmnet'; do
  set -- $row
  actual="$(TEST_IMSI="$1" QMICLI="$tmp/qmicli" sh "$helper" apn /dev/fixture)"
  [ "$actual" = "$2" ]
done

profile="$(TEST_IMSI=460150 QMICLI="$tmp/qmicli" sh "$helper" profile /dev/fixture)"
printf '%s\n' "$profile" | grep -qx 'AID=A0BC00DE0102FA04'
printf '%s\n' "$profile" | grep -qx 'MCCMNC=46015'
printf '%s\n' "$profile" | grep -qx 'APN=cbnet'
! printf '%s\n' "$profile" | grep -q '^IMSI='
echo Q410_SIM_PROFILE_TEST_PASS
