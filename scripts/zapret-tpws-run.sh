#!/bin/sh
# Foreground tpws for launchd KeepAlive supervision.
# NO --daemon: process stays in foreground so launchd restarts it instantly on exit.
# Args mirror upstream init.d/macos standard_mode_daemons (IPv4 hostlist mode).

set -e

ZAPRET_BASE="${ZAPRET_BASE:-/opt/zapret}"
ZAPRET_CONFIG="${ZAPRET_CONFIG:-$ZAPRET_BASE/config}"

if [ ! -f "$ZAPRET_CONFIG" ]; then
	echo "HATA: config yok: $ZAPRET_CONFIG" >&2
	exit 1
fi

# shellcheck disable=SC1090
. "$ZAPRET_CONFIG"
# shellcheck disable=SC1091
. "$ZAPRET_BASE/common/base.sh"
# shellcheck disable=SC1091
. "$ZAPRET_BASE/common/list.sh"

HOSTLIST_BASE="${HOSTLIST_BASE:-$ZAPRET_BASE/ipset}"
[ -n "$TPPORT" ] || TPPORT=988

TPWS="$ZAPRET_BASE/tpws/tpws"
if [ ! -x "$TPWS" ] && [ -x "$ZAPRET_BASE/binaries/my/tpws" ]; then
	TPWS="$ZAPRET_BASE/binaries/my/tpws"
fi
if [ ! -x "$TPWS" ]; then
	echo "HATA: tpws binary yok" >&2
	exit 1
fi

if [ "$TPWS_ENABLE" != "1" ]; then
	echo "TPWS_ENABLE!=1 — cikis" >&2
	exit 0
fi

# Build option string (same idea as macos/functions standard_mode_daemons)
opt="--user=root --port=$TPPORT"
if [ "$DISABLE_IPV4" != "1" ]; then
	opt="$opt --bind-addr=127.0.0.1"
fi
if [ "$DISABLE_IPV6" != "1" ]; then
	opt="$opt --bind-iface6=lo0 --bind-linklocal=force --bind-wait-ifup=30 --bind-wait-ip=30"
fi
opt="$opt $TPWS_OPT"
filter_apply_hostlist_target opt

# Strip daemon/pidfile if present in config (must not daemonize under KeepAlive)
opt=$(printf '%s' "$opt" | sed -e 's/--daemon//g' -e 's/--pidfile=[^ ]*//g')

# shellcheck disable=SC2086
exec "$TPWS" $opt
