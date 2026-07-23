#!/bin/sh
# Rollback to latest engine backup
set -e
. "$(dirname "$0")/lib.sh"
require_root

log_engine "=== Manuel motor rollback ==="

BACKUP_DIR=""
if [ -n "$1" ] && [ -d "$1" ]; then
	BACKUP_DIR="$1"
elif [ -f /opt/zapret.latest-backup ]; then
	BACKUP_DIR=$(cat /opt/zapret.latest-backup)
fi

if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
	# Find newest /opt/zapret.bak.*
	BACKUP_DIR=$(ls -1d /opt/zapret.bak.* 2>/dev/null | tail -1 || true)
fi

if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
	log_engine "HATA: Yedek bulunamadi (/opt/zapret.bak.*)"
	echo "Kullanilabilir yedek yok." >&2
	exit 1
fi

log_engine "Geri donuluyor: $BACKUP_DIR"
zapret_stop || true
rm -rf "$ZAPRET_OPT"
cp -a "$BACKUP_DIR" "$ZAPRET_OPT"
ln -fs "$ZAPRET_OPT/init.d/macos/zapret.plist" /Library/LaunchDaemons/zapret.plist
zapret_start || true
sleep 1
if is_running; then
	log_engine "Rollback OK — motor calisiyor."
	echo "Son motora donuldu: $BACKUP_DIR"
	exit 0
fi
log_engine "Rollback sonrasi tpws yok."
echo "Rollback yapildi ama tpws baslamadi. log: $ENGINE_UPDATE_LOG" >&2
exit 2
