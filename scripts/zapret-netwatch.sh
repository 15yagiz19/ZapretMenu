#!/bin/sh
# Poll network identity; on change apply saved profile or probe new network.
set +e
. "$(dirname "$0")/zapret-profile-lib.sh"

if ! desired_is_on; then
	exit 0
fi

if warp_connected; then
	exit 0
fi

load_net_id
[ -n "$NET_ID" ] || exit 0

last=""
if [ -f "$LAST_NET_FILE" ]; then
	last=$(tr -d ' \t\r\n' < "$LAST_NET_FILE")
fi

if [ "$NET_ID" = "$last" ]; then
	exit 0
fi

plog "network change: last=$last new=$NET_ID ssid=$NET_SSID"

ppath=$(profile_path "$NET_ID")
if [ -f "$ppath" ]; then
	"$(dirname "$0")/zapret-apply-profile.sh" "$NET_ID" >> "$NETWATCH_LOG" 2>&1
else
	# New network: probe (may take ~30s)
	"$(dirname "$0")/zapret-probe-network.sh" >> "$NETWATCH_LOG" 2>&1
fi
exit 0
