#!/bin/sh
# Switch MODE_FILTER: hostlist | autohostlist | none
# Usage: zapret-set-mode.sh [hostlist|autohostlist|none]
# Without arg: print current mode
set -e
. "$(dirname "$0")/lib.sh"
require_root

CFG="$ZAPRET_OPT/config"
[ -f "$CFG" ] || {
	echo "HATA: $CFG yok"
	exit 1
}

MODE=${1:-}
if [ -z "$MODE" ]; then
	grep -E '^MODE_FILTER=' "$CFG" || echo "MODE_FILTER=?"
	exit 0
fi

case "$MODE" in
	hostlist|autohostlist|none) ;;
	*)
		echo "Kullanim: zapret-set-mode.sh hostlist|autohostlist|none" >&2
		exit 2
		;;
esac

# Replace or append MODE_FILTER=
if grep -q '^MODE_FILTER=' "$CFG"; then
	tmp=$(mktemp)
	sed "s/^MODE_FILTER=.*/MODE_FILTER=$MODE/" "$CFG" > "$tmp"
	mv "$tmp" "$CFG"
else
	echo "MODE_FILTER=$MODE" >> "$CFG"
fi

# Ensure auto list file exists for autohostlist
mkdir -p "$ZAPRET_OPT/ipset"
touch "$ZAPRET_OPT/ipset/zapret-hosts-auto.txt"
touch "$ZAPRET_OPT/ipset/zapret-hosts-user-exclude.txt"
chmod 644 "$ZAPRET_OPT/ipset/zapret-hosts-auto.txt" 2>/dev/null || true

# Mirror to Application Support config if present
SUPPORT="/Library/Application Support/Zapret"
if [ -f "$SUPPORT/config/config.macos-hostlist" ]; then
	if grep -q '^MODE_FILTER=' "$SUPPORT/config/config.macos-hostlist"; then
		tmp=$(mktemp)
		sed "s/^MODE_FILTER=.*/MODE_FILTER=$MODE/" "$SUPPORT/config/config.macos-hostlist" > "$tmp"
		mv "$tmp" "$SUPPORT/config/config.macos-hostlist"
	fi
fi

log "MODE_FILTER=$MODE — tpws restart"
# Restart KeepAlive tpws so new MODE_FILTER is picked up
pkill -x tpws 2>/dev/null || true
sleep 1
if [ -f /Library/LaunchDaemons/zapret-tpws.plist ]; then
	launchctl bootout system/zapret-tpws 2>/dev/null || true
	launchctl bootstrap system /Library/LaunchDaemons/zapret-tpws.plist 2>/dev/null || \
		launchctl load -w /Library/LaunchDaemons/zapret-tpws.plist 2>/dev/null || true
fi
# Or use start path
if [ -x "$ZAPRET_OPT/local-tools/zapret-start.sh" ]; then
	# keep desired=on
	printf 'on\n' > "$SUPPORT/desired-state" 2>/dev/null || true
	"$ZAPRET_OPT/local-tools/zapret-start.sh" 2>/dev/null || true
fi

echo "OK MODE_FILTER=$MODE"
echo "autohostlist dosyasi: $ZAPRET_OPT/ipset/zapret-hosts-auto.txt"
exit 0
