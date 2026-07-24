#!/bin/sh
# Apply a network profile by id (default: current network id).
set -e
. "$(dirname "$0")/zapret-profile-lib.sh"

if ! desired_is_on; then
	plog "apply skip: desired=off"
	echo "SKIP desired=off"
	exit 0
fi

if warp_connected; then
	plog "apply skip: WARP connected"
	echo "SKIP warp"
	exit 0
fi

load_net_id
pid=${1:-$NET_ID}
[ -n "$pid" ] || {
	echo "ERROR no_network_id"
	exit 1
}

ppath=$(profile_path "$pid")
if [ ! -f "$ppath" ]; then
	echo "ERROR no_profile $pid"
	exit 1
fi

strat=$(read_profile_field "$ppath" strategy)
dnsmode=$(read_profile_field "$ppath" dns.mode)
quic=$(read_profile_field "$ppath" quic_block)
[ -n "$strat" ] || strat=tr-default
[ -n "$dnsmode" ] || dnsmode=public
[ -n "$quic" ] || quic=true

plog "apply profile=$pid strategy=$strat dns=$dnsmode quic=$quic"

case "$dnsmode" in
	router) apply_dns_router ;;
	*) apply_dns_public ;;
esac

apply_strategy_file "$strat" || true
apply_quic "$quic"
restart_tpws_keepalive
save_last_net "$pid"

ssid=$(read_profile_field "$ppath" ssid)
echo "APPLIED $pid strategy=$strat dns=$dnsmode ssid=$ssid"
exit 0
