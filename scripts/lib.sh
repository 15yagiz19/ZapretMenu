#!/bin/sh
# Shared helpers for Zapret scripts (portable — no hardcoded home paths)

# When sourced via `. "$(dirname "$0")/lib.sh"`, $0 is the calling script.
_SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

# System install layout: scripts in /opt/zapret/local-tools
# Dev/workspace layout: scripts in <repo>/scripts
case "$_SCRIPTS_DIR" in
	/opt/zapret/local-tools)
		_DEFAULT_HOME="/Library/Application Support/Zapret"
		_DEFAULT_UPSTREAM="/opt/zapret/src"
		;;
	*)
		_DEFAULT_HOME="$(CDPATH= cd -- "$_SCRIPTS_DIR/.." && pwd)"
		_DEFAULT_UPSTREAM="$_DEFAULT_HOME/upstream"
		;;
esac

ZAPRET_HOME="${ZAPRET_HOME:-$_DEFAULT_HOME}"
ZAPRET_OPT="${ZAPRET_OPT:-/opt/zapret}"
ZAPRET_INIT="${ZAPRET_INIT:-$ZAPRET_OPT/init.d/macos/zapret}"
ZAPRET_UPSTREAM="${ZAPRET_UPSTREAM:-$_DEFAULT_UPSTREAM}"
ZAPRET_LOG_DIR="${ZAPRET_LOG_DIR:-$ZAPRET_HOME/logs}"
ENGINE_UPDATE_LOG="${ENGINE_UPDATE_LOG:-$ZAPRET_LOG_DIR/engine-update.log}"
HOSTLIST_SRC="${HOSTLIST_SRC:-$ZAPRET_HOME/config/zapret-hosts-user.txt}"
CONFIG_SRC="${CONFIG_SRC:-$ZAPRET_HOME/config/config.macos-hostlist}"
ALLOWED_REMOTE="https://github.com/bol-van/zapret.git"
BACKUP_ROOT="${BACKUP_ROOT:-/opt}"
USER_NAME="${SUDO_USER:-$(id -un)}"

# desired-state: on|off — watchdog only restarts when "on"
SUPPORT_DIR_FIXED="/Library/Application Support/Zapret"
DESIRED_STATE_FILE="${DESIRED_STATE_FILE:-$SUPPORT_DIR_FIXED/desired-state}"

# launchd labels
ZAPRET_LAUNCHD_LABEL="${ZAPRET_LAUNCHD_LABEL:-system/zapret}"
ZAPRET_PLIST="${ZAPRET_PLIST:-/Library/LaunchDaemons/zapret.plist}"
WATCHDOG_LABEL="${WATCHDOG_LABEL:-system/zapret-watchdog}"
WATCHDOG_PLIST="${WATCHDOG_PLIST:-/Library/LaunchDaemons/zapret-watchdog.plist}"

mkdir -p "$ZAPRET_LOG_DIR" 2>/dev/null || true

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_engine() {
	mkdir -p "$ZAPRET_LOG_DIR" 2>/dev/null || true
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ENGINE_UPDATE_LOG"
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "Bu komut root gerektirir. Ornek: sudo $0 $*" >&2
		exit 1
	fi
}

is_running() {
	if pgrep -xq tpws 2>/dev/null; then
		return 0
	fi
	if [ -f /var/run/tpws1.pid ]; then
		pid=$(cat /var/run/tpws1.pid 2>/dev/null)
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			return 0
		fi
	fi
	return 1
}

set_desired_state() {
	_state=$1
	mkdir -p "$SUPPORT_DIR_FIXED" 2>/dev/null || true
	printf '%s\n' "$_state" > "$DESIRED_STATE_FILE"
	chmod 644 "$DESIRED_STATE_FILE" 2>/dev/null || true
}

get_desired_state() {
	if [ -f "$DESIRED_STATE_FILE" ]; then
		tr -d ' \t\r\n' < "$DESIRED_STATE_FILE" | tr '[:upper:]' '[:lower:]'
	else
		echo "on"
	fi
}

# Unload one-shot boot job so macOS cannot re-run start after Stop
zapret_launchd_unload() {
	launchctl bootout "$ZAPRET_LAUNCHD_LABEL" 2>/dev/null || true
	launchctl unload "$ZAPRET_PLIST" 2>/dev/null || true
}

zapret_launchd_load() {
	if [ -f "$ZAPRET_PLIST" ] || [ -L "$ZAPRET_PLIST" ]; then
		launchctl bootstrap system "$ZAPRET_PLIST" 2>/dev/null || \
			launchctl load -w "$ZAPRET_PLIST" 2>/dev/null || true
	fi
}

zapret_watchdog_load() {
	if [ -f "$WATCHDOG_PLIST" ] || [ -L "$WATCHDOG_PLIST" ]; then
		launchctl bootout "$WATCHDOG_LABEL" 2>/dev/null || true
		launchctl bootstrap system "$WATCHDOG_PLIST" 2>/dev/null || \
			launchctl load -w "$WATCHDOG_PLIST" 2>/dev/null || true
	fi
}

zapret_watchdog_unload() {
	launchctl bootout "$WATCHDOG_LABEL" 2>/dev/null || true
	launchctl unload "$WATCHDOG_PLIST" 2>/dev/null || true
}

zapret_start() {
	if [ ! -x "$ZAPRET_INIT" ]; then
		echo "HATA: $ZAPRET_INIT bulunamadi. Once system-install.sh calistirin." >&2
		return 1
	fi
	set_desired_state "on"
	# Boot job optional; we start daemons explicitly
	zapret_launchd_load
	zapret_watchdog_load
	"$ZAPRET_INIT" start
}

zapret_stop() {
	# User wants off — watchdog must not revive tpws
	set_desired_state "off"
	# Unload one-shot start job (not watchdog — it enforces off)
	zapret_launchd_unload
	if [ -x "$ZAPRET_INIT" ]; then
		"$ZAPRET_INIT" stop 2>/dev/null || true
	fi
	pkill -x tpws 2>/dev/null || true
	rm -f /var/run/tpws1.pid 2>/dev/null || true
	# Keep watchdog loaded so it can kill stray tpws if something restarts it
	zapret_watchdog_load
}

zapret_restart() {
	zapret_stop
	sleep 1
	zapret_start
}

zapret_status() {
	local state="Kapali"
	local desired
	desired=$(get_desired_state)
	if is_running; then
		state="Acik"
	fi
	echo "Zapret: $state"
	echo "desired: $desired"
	if is_running; then
		echo "tpws: calisiyor"
		pgrep -lf tpws 2>/dev/null | head -5
	else
		echo "tpws: yok"
		if [ "$desired" = "on" ]; then
			echo "not: desired=on ama tpws yok — watchdog ~30sn icinde baslatmali"
		fi
	fi
	if [ -f /etc/pf.anchors/zapret ]; then
		echo "PF anchor: mevcut"
	else
		echo "PF anchor: yok"
	fi
	if launchctl print system/zapret >/dev/null 2>&1; then
		echo "launchd zapret: kayitli"
	elif [ -L /Library/LaunchDaemons/zapret.plist ] || [ -f /Library/LaunchDaemons/zapret.plist ]; then
		echo "launchd zapret: plist var"
	else
		echo "launchd zapret: yok"
	fi
	if launchctl print system/zapret-watchdog >/dev/null 2>&1; then
		echo "watchdog: aktif (30sn)"
	elif [ -f /Library/LaunchDaemons/zapret-watchdog.plist ] || [ -L /Library/LaunchDaemons/zapret-watchdog.plist ]; then
		echo "watchdog: plist var ama unload"
	else
		echo "watchdog: yok"
	fi
	if [ -f "$ZAPRET_OPT/config" ]; then
		echo "config: $ZAPRET_OPT/config"
		grep -E '^(TPWS_ENABLE|MODE_FILTER|GETLIST|DISABLE_IPV6)=' "$ZAPRET_OPT/config" 2>/dev/null || true
	fi
	if [ -f "$ZAPRET_OPT/ipset/zapret-hosts-user.txt" ]; then
		echo "hostlist satir: $(grep -cve '^\s*#' -e '^\s*$' "$ZAPRET_OPT/ipset/zapret-hosts-user.txt" 2>/dev/null || echo 0)"
	fi
	[ "$state" = "Acik" ] && return 0 || return 1
}

sync_hostlist_to_opt() {
	if [ -f "$HOSTLIST_SRC" ]; then
		mkdir -p "$ZAPRET_OPT/ipset"
		cp "$HOSTLIST_SRC" "$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
		chmod 644 "$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
	fi
}

sync_config_to_opt() {
	if [ -f "$CONFIG_SRC" ]; then
		cp "$CONFIG_SRC" "$ZAPRET_OPT/config"
		chmod 644 "$ZAPRET_OPT/config"
	fi
	local custom_src="$ZAPRET_HOME/config/custom.d"
	local custom_dst="$ZAPRET_OPT/init.d/macos/custom.d"
	if [ -d "$custom_src" ]; then
		mkdir -p "$custom_dst"
		cp -f "$custom_src"/* "$custom_dst/" 2>/dev/null || true
		chmod 644 "$custom_dst"/* 2>/dev/null || true
	fi
}

sync_workspace_to_opt() {
	sync_hostlist_to_opt
	sync_config_to_opt
}

self_test_engine() {
	sleep 2
	if is_running; then
		return 0
	fi
	return 1
}
