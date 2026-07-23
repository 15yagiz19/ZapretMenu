#!/bin/sh
# Set Wi-Fi DNS to public resolvers (Turkey Discord DNS poison fix).
# No python3 / no Xcode CLT required.

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
	echo "Sistem Ayarlari > Wi-Fi > Ayrintilar > DNS:"
	echo "  $DNS1"
	echo "  $DNS2"
	echo "  $DNS3"
fi

dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "Kontrol (python YOK — dig/host kullanilir):"
sleep 1
IP=""
if command -v dig >/dev/null 2>&1; then
	IP=$(dig +short discord.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
fi
if [ -z "$IP" ] && command -v host >/dev/null 2>&1; then
	IP=$(host discord.com 2>/dev/null | awk '/has address/{print $4; exit}')
fi
if [ -z "$IP" ] && command -v nslookup >/dev/null 2>&1; then
	IP=$(nslookup discord.com 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)
fi
echo "  discord.com -> ${IP:-?}"
case "$IP" in
	195.175.254.*)
		echo "  KOTU: zehirli DNS. Router hâlâ DNS veriyor olabilir."
		echo "  Wi-Fi DNS'i elle 1.1.1.1 yapin; 'Otomatik' KAPALI olsun."
		;;
	162.159.*)
		echo "  IYI: Cloudflare Discord IP."
		;;
	"")
		echo "  IP okunamadi — yine de DNS ayari yazildiysa Discord'u yeniden acin."
		;;
	*)
		echo "  195.175.254.2 = kotu. 162.159.x.x = iyi."
		;;
esac
echo ""
echo "Simdi: Discord app'i Cmd+Q ile kapatip acin. WARP kapali olsun."
exit 0
