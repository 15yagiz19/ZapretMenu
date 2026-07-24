#!/bin/sh
# Probe current network: DNS poison + GitHub (Vencord) + strategy trial.
# Save profile + apply. Max ~60s. Discord.app + Vencord (no separate client).
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
ensure_github_hostlist_entries
sleep 1

notes=""
if discord_dns_poisoned; then
	notes="discord_dns_poison"
	plog "DNS poison signal discord"
	apply_dns_public
	sleep 1
fi
if github_dns_poisoned; then
	notes="${notes}; github_dns_poison"
	plog "DNS poison signal github"
	apply_dns_public
	dnsmode=public
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
github_ok_flag=0
# Safe trial order — success requires Discord/YouTube AND preferably GitHub (Vencord)
for strat in tr-default tr-split-soft tr-split-hard tr-split-midsld; do
	plog "trying strategy=$strat"
	apply_strategy_file "$strat" || continue
	apply_quic true
	restart_tpws_keepalive
	sleep 2
	discord_ok=0
	if curl_ok "https://discord.com" || curl_ok "https://www.youtube.com"; then
		discord_ok=1
	fi
	if [ "$discord_ok" -eq 1 ]; then
		if github_ok; then
			github_ok_flag=1
			best=$strat
			notes="${notes}; strategy=$strat discord+github ok"
			plog "strategy success (discord+github): $strat"
			break
		fi
		# Discord works but GitHub still bad — keep trying strategies once more for github
		best=$strat
		notes="${notes}; strategy=$strat discord_ok github_pending"
		plog "strategy partial (discord only): $strat"
	fi
done

if [ "$github_ok_flag" -eq 0 ]; then
	if github_ok; then
		github_ok_flag=1
		notes="${notes}; github_ok_after"
	else
		notes="${notes}; github_blocked"
		dnsmode=public
		apply_dns_public
		plog "WARNING: GitHub still blocked — Vencord may fail until network improves"
	fi
fi

if discord_dns_poisoned; then
	dnsmode=public
	apply_dns_public
	notes="${notes}; forced public DNS"
fi

write_profile "$NET_ID" "$NET_SSID" "$NET_GATEWAY" "$NET_IFACE" "$best" "$dnsmode" "$quic" "$notes"
"$(dirname "$0")/zapret-apply-profile.sh" "$NET_ID"
echo "PROBED $NET_ID strategy=$best dns=$dnsmode github=$github_ok_flag ssid=$NET_SSID display=$NET_DISPLAY notes=$notes"
exit 0
