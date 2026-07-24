#!/bin/sh
# Shared helpers for network profiles (sourced by apply/probe/netwatch)

SUPPORT_DIR="${SUPPORT_DIR:-/Library/Application Support/Zapret}"
PROFILES_DIR="${PROFILES_DIR:-$SUPPORT_DIR/profiles}"
STRATEGIES_DIR_OPT="/opt/zapret/local-tools/strategies"
LAST_NET_FILE="$SUPPORT_DIR/last_network_id"
ACTIVE_STRATEGY_FILE="$SUPPORT_DIR/active_strategy"
NETWATCH_LOG="$SUPPORT_DIR/logs/netwatch.log"
ZAPRET_OPT="${ZAPRET_OPT:-/opt/zapret}"
ZAPRET_INIT="${ZAPRET_INIT:-$ZAPRET_OPT/init.d/macos/zapret}"
TPWS_PLIST="/Library/LaunchDaemons/zapret-tpws.plist"
DESIRED_FILE="$SUPPORT_DIR/desired-state"

plog() {
	mkdir -p "$SUPPORT_DIR/logs" 2>/dev/null || true
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$NETWATCH_LOG" 2>/dev/null
}

desired_is_on() {
	d=on
	if [ -f "$DESIRED_FILE" ]; then
		d=$(tr -d ' \t\r\n' < "$DESIRED_FILE" | tr '[:upper:]' '[:lower:]')
	fi
	case "$d" in
		off|0|false|no) return 1 ;;
		*) return 0 ;;
	esac
}

strategies_dir() {
	if [ -d "$STRATEGIES_DIR_OPT" ]; then
		echo "$STRATEGIES_DIR_OPT"
	elif [ -d "$(dirname "$0")/../config/strategies" ]; then
		echo "$(CDPATH= cd -- "$(dirname "$0")/../config/strategies" && pwd)"
	else
		echo "$STRATEGIES_DIR_OPT"
	fi
}

profile_path() {
	echo "$PROFILES_DIR/$1.json"
}

load_net_id() {
	NET_SSID=""
	NET_GATEWAY=""
	NET_IFACE=""
	NET_IFNAME=""
	NET_ID=""
	NET_DISPLAY=""
	_nid="$("$(dirname "$0")/zapret-net-id.sh" 2>/dev/null)"
	NET_SSID=$(printf '%s\n' "$_nid" | sed -n 's/^ssid=//p' | head -1)
	NET_GATEWAY=$(printf '%s\n' "$_nid" | sed -n 's/^gateway=//p' | head -1)
	NET_IFACE=$(printf '%s\n' "$_nid" | sed -n 's/^iface=//p' | head -1)
	NET_IFNAME=$(printf '%s\n' "$_nid" | sed -n 's/^ifname=//p' | head -1)
	NET_ID=$(printf '%s\n' "$_nid" | sed -n 's/^id=//p' | head -1)
	NET_DISPLAY=$(printf '%s\n' "$_nid" | sed -n 's/^display=//p' | head -1)
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_profile() {
	_id=$1
	_ssid=$2
	_gw=$3
	_iface=$4
	_strat=$5
	_dnsmode=$6
	_quic=$7
	_notes=$8
	mkdir -p "$PROFILES_DIR"
	_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	_path=$(profile_path "$_id")
	_created=$_now
	if [ -f "$_path" ]; then
		_c=$(sed -n 's/.*"created"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_path" | head -1)
		[ -n "$_c" ] && _created=$_c
	fi
	cat > "$_path" <<JSON
{
  "id": "$(json_escape "$_id")",
  "ssid": "$(json_escape "$_ssid")",
  "gateway": "$(json_escape "$_gw")",
  "iface": "$(json_escape "$_iface")",
  "created": "$_created",
  "updated": "$_now",
  "dns": {
    "mode": "$(json_escape "$_dnsmode")",
    "servers": ["1.1.1.1", "1.0.0.1", "8.8.8.8"]
  },
  "strategy": "$(json_escape "$_strat")",
  "quic_block": $_quic,
  "disable_ipv6": true,
  "notes": "$(json_escape "$_notes")"
}
JSON
	chmod 644 "$_path" 2>/dev/null || true
	plog "profile saved: $_id strategy=$_strat dns=$_dnsmode quic=$_quic"
}

read_profile_field() {
	_p=$1
	_f=$2
	[ -f "$_p" ] || return 1
	case "$_f" in
		dns.mode)
			sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_p" | head -1
			;;
		quic_block)
			if grep -q '"quic_block"[[:space:]]*:[[:space:]]*true' "$_p" 2>/dev/null; then
				echo true
			else
				echo false
			fi
			;;
		*)
			sed -n "s/.*\"$_f\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$_p" | head -1
			;;
	esac
}

warp_connected() {
	if scutil --nc list 2>/dev/null | grep -qiE 'Connected.*[Ww]arp|Connected.*Cloudflare'; then
		return 0
	fi
	return 1
}

discord_dns_poisoned() {
	ip=""
	if command -v dig >/dev/null 2>&1; then
		ip=$(dig +short +time=2 +tries=1 discord.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
	fi
	if [ -z "$ip" ] && command -v host >/dev/null 2>&1; then
		ip=$(host discord.com 2>/dev/null | awk '/has address/{print $4; exit}')
	fi
	case "$ip" in
		195.175.254.*) return 0 ;;
		*) return 1 ;;
	esac
}

curl_ok() {
	url=$1
	code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -I "$url" 2>/dev/null || echo 000)
	case "$code" in
		2*|3*) return 0 ;;
		*) return 1 ;;
	esac
}

# Vencord on Discord.app needs GitHub API + site reachable (not just discord.com)
github_ok() {
	if curl_ok "https://api.github.com" || curl_ok "https://github.com"; then
		return 0
	fi
	return 1
}

github_dns_poisoned() {
	ip=""
	if command -v dig >/dev/null 2>&1; then
		ip=$(dig +short +time=2 +tries=1 api.github.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
	fi
	case "$ip" in
		195.175.254.*|127.*|0.0.0.0) return 0 ;;
		*) return 1 ;;
	esac
}

# Ensure Support + /opt hostlists include GitHub/Vencord domains (merge, no wipe)
ensure_github_hostlist_entries() {
	_hl="$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
	_sup="$SUPPORT_DIR/config/zapret-hosts-user.txt"
	_add='
api.github.com
raw.githubusercontent.com
objects.githubusercontent.com
release-assets.githubusercontent.com
camo.githubusercontent.com
vencord.dev
vencord.cc
github.com
githubusercontent.com
githubassets.com
github.io
'
	for _f in "$_hl" "$_sup"; do
		[ -f "$_f" ] || continue
		printf '%s\n' "$_add" | while IFS= read -r d; do
			[ -z "$d" ] && continue
			grep -qxF "$d" "$_f" 2>/dev/null || echo "$d" >> "$_f"
		done
	done
}

apply_dns_public() {
	for svc in "Wi-Fi" "Ethernet" "USB 10/100/1000 LAN" "Thunderbolt Ethernet"; do
		networksetup -setdnsservers "$svc" 1.1.1.1 1.0.0.1 8.8.8.8 2>/dev/null || true
	done
	dscacheutil -flushcache 2>/dev/null || true
	killall -HUP mDNSResponder 2>/dev/null || true
}

apply_dns_router() {
	for svc in "Wi-Fi" "Ethernet" "USB 10/100/1000 LAN" "Thunderbolt Ethernet"; do
		networksetup -setdnsservers "$svc" Empty 2>/dev/null || true
	done
	dscacheutil -flushcache 2>/dev/null || true
	killall -HUP mDNSResponder 2>/dev/null || true
}

apply_strategy_file() {
	strat=$1
	sdir=$(strategies_dir)
	src="$sdir/${strat}.tpws"
	if [ ! -f "$src" ]; then
		plog "strategy file missing: $src — fallback tr-default"
		src="$sdir/tr-default.tpws"
	fi
	[ -f "$src" ] || return 1
	body=$(cat "$src")
	cfg="$ZAPRET_OPT/config"
	[ -f "$cfg" ] || return 1
	tmp=$(mktemp)
	awk '
		BEGIN{skip=0}
		/^TPWS_OPT="/ {skip=1; next}
		skip==1 && /^"/ {skip=0; next}
		skip==1 {next}
		{print}
	' "$cfg" > "$tmp"
	{
		cat "$tmp"
		echo "TPWS_OPT=\""
		printf '%s\n' "$body"
		echo "\""
	} > "$cfg.new"
	mv "$cfg.new" "$cfg"
	rm -f "$tmp"
	printf '%s\n' "$strat" > "$ACTIVE_STRATEGY_FILE"
	plog "strategy applied: $strat"
}

apply_quic() {
	want=$1
	custom_d="$ZAPRET_OPT/init.d/macos/custom.d"
	mkdir -p "$custom_d"
	if [ "$want" = "true" ]; then
		if [ -f "$(dirname "$0")/../config/custom.d/10-block-quic" ]; then
			cp "$(dirname "$0")/../config/custom.d/10-block-quic" "$custom_d/10-block-quic"
		elif [ ! -f "$custom_d/10-block-quic" ]; then
			cat > "$custom_d/10-block-quic" <<'Q'
# Block QUIC (UDP/443)
zapret_custom_firewall_v4()
{
	echo "block drop out quick inet proto udp from any to any port 443"
}
zapret_custom_firewall_v6()
{
	echo "block drop out quick inet6 proto udp from any to any port 443"
}
Q
		fi
		chmod 644 "$custom_d/10-block-quic" 2>/dev/null || true
		plog "quic_block=on"
	else
		rm -f "$custom_d/10-block-quic"
		plog "quic_block=off"
	fi
}

restart_tpws_keepalive() {
	if [ -x "$ZAPRET_INIT" ]; then
		"$ZAPRET_INIT" restart-fw 2>/dev/null || {
			"$ZAPRET_INIT" stop-fw 2>/dev/null || true
			"$ZAPRET_INIT" start-fw 2>/dev/null || true
		}
	fi
	pkill -x tpws 2>/dev/null || true
	rm -f /var/run/tpws1.pid 2>/dev/null || true
	if [ -f "$TPWS_PLIST" ]; then
		launchctl bootout system/zapret-tpws 2>/dev/null || true
		sleep 0.3
		launchctl bootstrap system "$TPWS_PLIST" 2>/dev/null || \
			launchctl load -w "$TPWS_PLIST" 2>/dev/null || true
	fi
	sleep 1
}

save_last_net() {
	mkdir -p "$SUPPORT_DIR"
	printf '%s\n' "$1" > "$LAST_NET_FILE"
}
