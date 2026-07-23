#!/bin/sh
# Boot once: if desired=on, apply PF and ensure KeepAlive tpws job is loaded.
set +e
SUPPORT="/Library/Application Support/Zapret"
DESIRED_FILE="$SUPPORT/desired-state"
INIT="/opt/zapret/init.d/macos/zapret"
PLIST="/Library/LaunchDaemons/zapret-tpws.plist"
LOG="$SUPPORT/logs/boot.log"

mkdir -p "$SUPPORT/logs" 2>/dev/null || true
logb() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

desired="on"
if [ -f "$DESIRED_FILE" ]; then
	desired=$(tr -d ' \t\r\n' < "$DESIRED_FILE" | tr '[:upper:]' '[:lower:]')
fi
[ -z "$desired" ] && desired="on"

if [ "$desired" != "on" ] && [ "$desired" != "1" ] && [ "$desired" != "true" ]; then
	logb "desired=$desired — boot skip (tpws job not loaded)"
	# Ensure KeepAlive job not running
	launchctl bootout system/zapret-tpws 2>/dev/null || true
	exit 0
fi

logb "desired=on — PF + KeepAlive tpws"
if [ -x "$INIT" ]; then
	"$INIT" start-fw >> "$LOG" 2>&1 || "$INIT" start-fw 2>/dev/null || true
fi
# Kill any leftover daemonized tpws (old model) before KeepAlive takes over
pkill -x tpws 2>/dev/null || true
rm -f /var/run/tpws1.pid 2>/dev/null || true
sleep 0.5

if [ -f "$PLIST" ]; then
	launchctl bootout system/zapret-tpws 2>/dev/null || true
	launchctl bootstrap system "$PLIST" 2>/dev/null || \
		launchctl load -w "$PLIST" 2>/dev/null || true
	logb "zapret-tpws KeepAlive loaded"
else
	logb "HATA: $PLIST yok"
	exit 1
fi
exit 0
