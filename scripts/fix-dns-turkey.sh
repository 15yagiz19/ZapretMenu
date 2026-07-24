#!/bin/sh
# Set Wi-Fi DNS to public resolvers and save into current network profile.
set +e

DNS1=1.1.1.1
DNS2=1.0.0.1
DNS3=8.8.8.8

echo "=== DNS duzelt (Turkiye / Discord) ==="
echo "Hedef: $DNS1  $DNS2  $DNS3"
echo ""

apply_dns() {
	_svc=$1
	[ -z "$_svc" ] && return 1
	if networksetup -setdnsservers "$_svc" "$DNS1" "$DNS2" "$DNS3" 2>/dev/null; then
		_cur=$(networksetup -getdnsservers "$_svc" 2>/dev/null | tr '\n' ' ')
		echo "OK: $_svc -> $_cur"
		return 0
	fi
	return 1
}

FIXED=0
if [ -n "$1" ]; then
	apply_dns "$1" && FIXED=1
else
	for svc in "Wi-Fi" "Ethernet" "USB 10/100/1000 LAN" "Thunderbolt Ethernet"; do
		apply_dns "$svc" && FIXED=1
	done
fi

if [ "$FIXED" -eq 0 ]; then
	echo "UYARI: DNS yazilamadi."
fi

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

# Save into current network profile (best effort)
if [ -f "$(dirname "$0")/zapret-profile-lib.sh" ]; then
	# shellcheck disable=SC1091
	. "$(dirname "$0")/zapret-profile-lib.sh"
	load_net_id
	if [ -n "$NET_ID" ]; then
		ppath=$(profile_path "$NET_ID")
		strat=tr-default
		quic=true
		if [ -f "$ppath" ]; then
			s=$(read_profile_field "$ppath" strategy)
			q=$(read_profile_field "$ppath" quic_block)
			[ -n "$s" ] && strat=$s
			[ -n "$q" ] && quic=$q
		fi
		write_profile "$NET_ID" "$NET_SSID" "$NET_GATEWAY" "$NET_IFACE" "$strat" "public" "$quic" "manual DNS fix"
		echo "Profil guncellendi: $NET_DISPLAY ($NET_ID) dns=public"
	fi
fi

echo ""
echo "Kontrol:"
sleep 1
IP=""
if command -v dig >/dev/null 2>&1; then
	IP=$(dig +short discord.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
fi
echo "  discord.com -> ${IP:-?}"
case "$IP" in
	195.175.254.*) echo "  KOTU: zehirli DNS" ;;
	162.159.*) echo "  IYI: Cloudflare" ;;
	*) echo "  Not: 195.175.254.2 = kotu" ;;
esac
echo "  Discord app + tarayiciyi kapatip acin."
exit 0
