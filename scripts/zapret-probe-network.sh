#!/bin/sh
# Probe current network: DNS poison + strategy trial. Save profile + apply.
# Max ~60s. Usage: zapret-probe-network.sh
set +e
. "$(dirname "$0")/zapret-profile-lib.sh"

if ! desired_is_on; then
	echo "SKIP desired=off"
	exit 0
fi

if warp_connected; then
	echo "SKIP warp — Cloudflare WARP kapatip tekrar deneyin"
	exit 0
fi

load_net_id
[ -n "$NET_ID" ] || {
	echo "ERROR no_network"
	exit 1
}

plog "probe start id=$NET_ID ssid=$NET_SSID gw=$NET_GATEWAY"

# Always prefer public DNS on Turkish consumer networks (safe default)
dnsmode=public
apply_dns_public
sleep 1

notes=""
if discord_dns_poisoned; then
	notes="auto: discord DNS poison detected after public DNS still bad or was poisoned"
	plog "DNS poison signal (pre/post)"
	apply_dns_public
	sleep 1
fi

# Ensure tpws up for strategy trials
if ! pgrep -xq tpws 2>/dev/null; then
	if [ -x /usr/local/bin/zapret-ctl ]; then
		/usr/local/bin/zapret-ctl start >/dev/null 2>&1
	fi
	restart_tpws_keepalive
fi

best=tr-default
quic=true
# Safe trial order
for strat in tr-default tr-split-soft tr-split-hard tr-split-midsld; do
	plog "trying strategy=$strat"
	apply_strategy_file "$strat" || continue
	apply_quic true
	restart_tpws_keepalive
	sleep 2
	if curl_ok "https://www.apple.com" || curl_ok "https://discord.com"; then
		if curl_ok "https://discord.com" || curl_ok "https://www.youtube.com"; then
			best=$strat
			notes="${notes}; strategy=$strat ok"
			plog "strategy success: $strat"
			break
		fi
	fi
done

# If discord still poisoned, force public again
if discord_dns_poisoned; then
	dnsmode=public
	apply_dns_public
	notes="${notes}; forced public DNS"
fi

write_profile "$NET_ID" "$NET_SSID" "$NET_GATEWAY" "$NET_IFACE" "$best" "$dnsmode" "$quic" "$notes"
# apply already partially done; finalize
"$(dirname "$0")/zapret-apply-profile.sh" "$NET_ID"
echo "PROBED $NET_ID strategy=$best dns=$dnsmode ssid=$NET_SSID display=$NET_DISPLAY"
exit 0
