#!/bin/sh
# Print current network + profile status (for menubar/CLI)
set +e
. "$(dirname "$0")/zapret-profile-lib.sh"

load_net_id
echo "ssid=$NET_SSID"
echo "gateway=$NET_GATEWAY"
echo "iface=$NET_IFACE"
echo "id=$NET_ID"
echo "display=$NET_DISPLAY"

last=""
if [ -f "$LAST_NET_FILE" ]; then
	last=$(tr -d ' \t\r\n' < "$LAST_NET_FILE")
fi
echo "last_applied=$last"

ppath=$(profile_path "$NET_ID")
if [ -f "$ppath" ]; then
	echo "profile=yes"
	echo "strategy=$(read_profile_field "$ppath" strategy)"
	echo "dns_mode=$(read_profile_field "$ppath" dns.mode)"
	echo "quic_block=$(read_profile_field "$ppath" quic_block)"
else
	echo "profile=no"
fi

if [ -f "$ACTIVE_STRATEGY_FILE" ]; then
	echo "active_strategy=$(tr -d '\n' < "$ACTIVE_STRATEGY_FILE")"
fi

if desired_is_on; then
	echo "desired=on"
else
	echo "desired=off"
fi

if warp_connected; then
	echo "warp=yes"
else
	echo "warp=no"
fi

if discord_dns_poisoned; then
	echo "discord_dns=poison"
else
	echo "discord_dns=ok_or_unknown"
fi

# DNS servers on Wi-Fi
dns=$(networksetup -getdnsservers "Wi-Fi" 2>/dev/null | tr '\n' ' ')
echo "wifi_dns=$dns"
exit 0
