#!/bin/sh
# Shared helpers for Zapret scripts (portable — no hardcoded home paths)
# v1.0.7: KeepAlive launchd supervises foreground tpws (instant restart)

_SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

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

SUPPORT_DIR_FIXED="/Library/Application Support/Zapret"
DESIRED_STATE_FILE="${DESIRED_STATE_FILE:-$SUPPORT_DIR_FIXED/desired-state}"

# KeepAlive supervised tpws (primary)
TPWS_LABEL="${TPWS_LABEL:-system/zapret-tpws}"
TPWS_PLIST="${TPWS_PLIST:-/Library/LaunchDaemons/zapret-tpws.plist}"
# Boot loader (desired=on → load KeepAlive + PF)
BOOT_LABEL="${BOOT_LABEL:-system/zapret-boot}"
BOOT_PLIST="${BOOT_PLIST:-/Library/LaunchDaemons/zapret-boot.plist}"
# Legacy one-shot + 30s watchdog (disabled when KeepAlive is active)
LEGACY_LABEL="${LEGACY_LABEL:-system/zapret}"
LEGACY_PLIST="${LEGACY_PLIST:-/Library/LaunchDaemons/zapret.plist}"
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

# Unload legacy one-shot + 30s watchdog (KeepAlive replaces them)
zapret_legacy_unload() {
	launchctl bootout "$LEGACY_LABEL" 2>/dev/null || true
	launchctl unload "$LEGACY_PLIST" 2>/dev/null || true
	launchctl bootout "$WATCHDOG_LABEL" 2>/dev/null || true
	launchctl unload "$WATCHDOG_PLIST" 2>/dev/null || true
}

zapret_tpws_unload() {
	launchctl bootout "$TPWS_LABEL" 2>/dev/null || true
	launchctl unload "$TPWS_PLIST" 2>/dev/null || true
}

zapret_tpws_load() {
	if [ ! -f "$TPWS_PLIST" ] && [ ! -L "$TPWS_PLIST" ]; then
		echo "HATA: $TPWS_PLIST yok — system-install ile kurun." >&2
		return 1
	fi
	# Kill daemonized leftovers so only KeepAlive instance runs
	pkill -x tpws 2>/dev/null || true
	rm -f /var/run/tpws1.pid 2>/dev/null || true
	sleep 0.3
	launchctl bootout "$TPWS_LABEL" 2>/dev/null || true
	launchctl bootstrap system "$TPWS_PLIST" 2>/dev/null || \
		launchctl load -w "$TPWS_PLIST" 2>/dev/null || true
}

zapret_boot_load() {
	if [ -f "$BOOT_PLIST" ] || [ -L "$BOOT_PLIST" ]; then
		launchctl bootout "$BOOT_LABEL" 2>/dev/null || true
		launchctl bootstrap system "$BOOT_PLIST" 2>/dev/null || \
			launchctl load -w "$BOOT_PLIST" 2>/dev/null || true
	fi
}

zapret_start() {
	if [ ! -x "$ZAPRET_INIT" ]; then
		echo "HATA: $ZAPRET_INIT bulunamadi." >&2
		return 1
	fi
	set_desired_state "on"
	zapret_legacy_unload
	# PF rules first, then KeepAlive tpws (no --daemon)
	"$ZAPRET_INIT" start-fw 2>/dev/null || "$ZAPRET_INIT" start-fw || true
	zapret_tpws_load || return 1
	zapret_boot_load
	sleep 1
	if is_running; then
		return 0
	fi
	# brief wait for launchd spawn
	sleep 2
	is_running
}

zapret_stop() {
	set_desired_state "off"
	# Unload KeepAlive FIRST so it cannot revive
	zapret_tpws_unload
	zapret_legacy_unload
	if [ -x "$ZAPRET_INIT" ]; then
		"$ZAPRET_INIT" stop-fw 2>/dev/null || true
		"$ZAPRET_INIT" stop-daemons 2>/dev/null || true
	fi
	pkill -x tpws 2>/dev/null || true
	rm -f /var/run/tpws1.pid 2>/dev/null || true
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
			echo "not: desired=on ama tpws yok — KeepAlive aninda baslatmali"
		fi
	fi
	if [ -f /etc/pf.anchors/zapret ]; then
		echo "PF anchor: mevcut"
	else
		echo "PF anchor: yok"
	fi
	if launchctl print system/zapret-tpws >/dev/null 2>&1; then
		echo "launchd tpws: KeepAlive aktif"
	elif [ -f "$TPWS_PLIST" ] || [ -L "$TPWS_PLIST" ]; then
		echo "launchd tpws: plist var (unload — Kapat sonrasi normal)"
	else
		echo "launchd tpws: yok"
	fi
	if launchctl print system/zapret-boot >/dev/null 2>&1; then
		echo "launchd boot: kayitli"
	elif [ -f "$BOOT_PLIST" ]; then
		echo "launchd boot: plist var"
	else
		echo "launchd boot: yok"
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
