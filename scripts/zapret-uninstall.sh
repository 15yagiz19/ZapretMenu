#!/bin/sh
# Uninstall zapret (requires confirmation)
set -e
. "$(dirname "$0")/lib.sh"
require_root

if [ "$1" != "--yes" ]; then
	echo "Zapret tamamen kaldirilacak: /opt/zapret, launchd, PF anchor."
	echo "Onay icin: sudo $0 --yes"
	exit 1
fi

log "Zapret kaldiriliyor..."
if [ -x "$ZAPRET_INIT" ]; then
	"$ZAPRET_INIT" stop 2>/dev/null || true
fi
pkill -x tpws 2>/dev/null || true

# Prefer official uninstall if present
if [ -x "$ZAPRET_OPT/uninstall_easy.sh" ]; then
	# uninstall_easy may be interactive; do manual cleanup as primary
	:
fi

# launchd
launchctl bootout system/zapret 2>/dev/null || true
rm -f /Library/LaunchDaemons/zapret.plist

# PF anchors (from official helpers if available)
if [ -f "$ZAPRET_OPT/common/pf.sh" ] && [ -f "$ZAPRET_OPT/config" ]; then
	# shellcheck disable=SC1090
	export ZAPRET_BASE="$ZAPRET_OPT"
	# shellcheck disable=SC1091
	. "$ZAPRET_OPT/config"
	# shellcheck disable=SC1091
	. "$ZAPRET_OPT/common/base.sh"
	# shellcheck disable=SC1091
	. "$ZAPRET_OPT/common/pf.sh"
	pf_anchors_clear 2>/dev/null || true
	pf_anchors_del 2>/dev/null || true
	pf_anchor_root_del 2>/dev/null || true
	pfctl -qf /etc/pf.conf 2>/dev/null || true
fi

# Remove PF anchor files if leftover
rm -f /etc/pf.anchors/zapret /etc/pf.anchors/zapret-v4 /etc/pf.anchors/zapret-v6

# Backup then remove /opt/zapret
TS=$(date +%Y%m%d-%H%M%S)
if [ -d "$ZAPRET_OPT" ]; then
	mv "$ZAPRET_OPT" "/opt/zapret.removed.$TS"
	log "Eski kurulum: /opt/zapret.removed.$TS"
fi

# Optional: sudoers + ctl
rm -f /etc/sudoers.d/zapret-toggle
rm -f /usr/local/bin/zapret-ctl

rm -rf "/Library/Application Support/Zapret" 2>/dev/null || true

log "Kaldirma tamam. Menubar app: /Applications/ZapretToggle.app elle silinebilir."
log "PF yedegi (varsa): /Library/Application Support/Zapret/backups/ veya $ZAPRET_HOME/backups/"
exit 0
