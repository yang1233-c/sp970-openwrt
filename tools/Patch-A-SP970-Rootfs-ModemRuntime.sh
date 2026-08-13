#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
	echo "usage: $0 IMAGE RMTFS TQFTPSERV INIT_SCRIPT" >&2
	exit 2
fi

image=$1
rmtfs=$2
tqftp=$3
init_script=$4
verify_dir=/tmp/q410-rootfs-modem-verify

test -f "$image"
test -f "$rmtfs"
test -f "$tqftp"
test -f "$init_script"

replace_file() {
	source=$1
	target=$2
	debugfs -w -R "rm $target" "$image" >/dev/null 2>&1 || true
	debugfs -w -R "write $source $target" "$image"
	debugfs -w -R "set_inode_field $target mode 0100755" "$image"
}

replace_file "$rmtfs" /usr/sbin/rmtfs
replace_file "$tqftp" /usr/bin/tqftpserv
replace_file "$init_script" /etc/init.d/sp970-modem

e2fsck -fy "$image"

echo '=== STAT ==='
debugfs -R 'stat /usr/sbin/rmtfs' "$image" 2>/dev/null | head -8
debugfs -R 'stat /usr/bin/tqftpserv' "$image" 2>/dev/null | head -8
debugfs -R 'stat /etc/init.d/sp970-modem' "$image" 2>/dev/null | head -8

rm -rf "$verify_dir"
mkdir -p "$verify_dir"
debugfs -R "dump /usr/sbin/rmtfs $verify_dir/rmtfs" "$image" >/dev/null
debugfs -R "dump /usr/bin/tqftpserv $verify_dir/tqftpserv" "$image" >/dev/null
debugfs -R "dump /etc/init.d/sp970-modem $verify_dir/sp970-modem" "$image" >/dev/null

echo '=== DUMP VERIFY ==='
sha256sum "$verify_dir/rmtfs" "$verify_dir/tqftpserv" "$verify_dir/sp970-modem"

test "$(sha256sum "$verify_dir/rmtfs" | awk '{print $1}')" = \
	0e29b8b635c937277c2a11adf8b79b7217a83b63eeacb536c44d0e02a2af6d59
test "$(sha256sum "$verify_dir/tqftpserv" | awk '{print $1}')" = \
	e3bf31e3526df6edb2e03dfaa1ff1d359be08bfe56277973b7e83854435c9a41
test "$(sha256sum "$verify_dir/sp970-modem" | awk '{print $1}')" = \
	43a02c6a012bcb9a18b7ff4478ce53c140795a6e0209b144f0c754671a1009a3

echo ROOTFS_MODEM_RUNTIME_PATCH_PASS
