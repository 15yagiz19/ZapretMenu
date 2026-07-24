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

# Vencord needs GitHub domains in hostlist always
ensure_github_hostlist_entries

# If profile notes mention github_blocked, force public DNS even if mode was router
notes=$(read_profile_field "$ppath" notes)
case "$notes" in
	*github_blocked*|*github_dns_poison*)
		dnsmode=public
		plog "notes force public DNS (github)"
		;;
esac

case "$dnsmode" in
	router) apply_dns_router ;;
	*) apply_dns_public ;;
esac

apply_strategy_file "$strat" || true
apply_quic "$quic"
restart_tpws_keepalive
save_last_net "$pid"

ssid=$(read_profile_field "$ppath" ssid)
gh=no
if github_ok; then gh=yes; fi
echo "APPLIED $pid strategy=$strat dns=$dnsmode ssid=$ssid github=$gh"
exit 0
