#!/bin/sh
# Restart tpws if desired-state is "on" but process is missing.
# Invoked every ~30s by LaunchDaemon zapret-watchdog.
# Does NOT force-start when user requested off.

set +e

SUPPORT_DIR="/Library/Application Support/Zapret"
DESIRED_FILE="$SUPPORT_DIR/desired-state"
LOG_DIR="$SUPPORT_DIR/logs"
LOG="$LOG_DIR/watchdog.log"
ZAPRET_INIT="/opt/zapret/init.d/macos/zapret"
LOCAL_TOOLS="/opt/zapret/local-tools"

mkdir -p "$LOG_DIR" 2>/dev/null || true

logw() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null || true
}

# Cap log size (~512KB)
if [ -f "$LOG" ]; then
	sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
	if [ "$sz" -gt 524288 ] 2>/dev/null; then
		tail -c 131072 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
fi

desired="on"
if [ -f "$DESIRED_FILE" ]; then
	desired=$(tr -d ' \t\r\n' < "$DESIRED_FILE" | tr '[:upper:]' '[:lower:]')
fi
# Default on if missing (fresh install / upgrade)
if [ -z "$desired" ]; then
	desired="on"
fi

tpws_up=0
if pgrep -xq tpws 2>/dev/null; then
	tpws_up=1
elif [ -f /var/run/tpws1.pid ]; then
	pid=$(cat /var/run/tpws1.pid 2>/dev/null)
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		tpws_up=1
	fi
fi

case "$desired" in
	on|1|true|yes)
		if [ "$tpws_up" -eq 0 ]; then
			logw "desired=on ama tpws yok — yeniden baslatiliyor"
			if [ -x "$ZAPRET_INIT" ]; then
				"$ZAPRET_INIT" start >> "$LOG" 2>&1
				rc=$?
				sleep 1
				if pgrep -xq tpws 2>/dev/null; then
					logw "OK: tpws yeniden baslatildi (rc=$rc)"
				else
					logw "HATA: tpws hâlâ yok (rc=$rc)"
				fi
			else
				logw "HATA: $ZAPRET_INIT yok"
			fi
		fi
		;;
	off|0|false|no)
		if [ "$tpws_up" -eq 1 ]; then
			logw "desired=off ama tpws calisiyor — durduruluyor"
			if [ -x "$ZAPRET_INIT" ]; then
				"$ZAPRET_INIT" stop >> "$LOG" 2>&1 || true
			fi
			pkill -x tpws 2>/dev/null || true
			rm -f /var/run/tpws1.pid 2>/dev/null || true
		fi
		;;
	*)
		logw "bilinmeyen desired-state: $desired"
		;;
esac
exit 0
