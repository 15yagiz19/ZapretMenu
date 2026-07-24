#!/bin/sh
# Diagnose Discord.app + Vencord vs Zapret network (read-only).
# Official Discord.app + Vencord only (no alternate client).
set +e

SUPPORT="/Library/Application Support/Zapret"
ZAPRET_OPT="/opt/zapret"

echo "=== Zapret Discord/Vencord diag ==="
echo "goal=Discord.app+Vencord (no alternate client)"

desired=on
if [ -f "$SUPPORT/desired-state" ]; then
	desired=$(tr -d ' \t\r\n' < "$SUPPORT/desired-state" | tr '[:upper:]' '[:lower:]')
fi
echo "desired=$desired"
if pgrep -xq tpws 2>/dev/null; then
	echo "tpws=yes"
else
	echo "tpws=no"
fi

# --- Discord DNS ---
dip=""
if command -v dig >/dev/null 2>&1; then
	dip=$(dig +short +time=3 +tries=2 discord.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
fi
echo "discord_dns_ip=${dip:-?}"
discord_poison=no
case "$dip" in
	195.175.254.*) discord_poison=yes ;;
esac
echo "discord_dns_poison=$discord_poison"

# Real Cloudflare Discord ranges often 162.159.x — treat as healthy DNS
discord_dns_ok=no
case "$dip" in
	162.159.*|104.16.*|104.17.*|104.18.*|104.19.*|104.20.*|104.21.*|172.64.*|172.65.*|172.66.*|172.67.*)
		discord_dns_ok=yes
		;;
esac
if [ "$discord_poison" = "yes" ]; then
	discord_dns_ok=no
fi
echo "discord_dns_ok=$discord_dns_ok"

# --- Discord HTTPS: prefer GET (HEAD sometimes returns 000 spuriously) ---
http_code() {
	url=$1
	# GET with range to avoid huge body; follow redirects
	c=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 6 --max-time 12 \
		-L -A "ZapretMenu-diag/1.0" "$url" 2>/dev/null || echo 000)
	# collapse multi-code glitches
	c=$(printf '%s' "$c" | tr -cd '0-9' | tail -c 3)
	[ -n "$c" ] || c=000
	printf '%s' "$c"
}

dcode=$(http_code "https://discord.com")
if [ "$dcode" = "000" ]; then
	dcode=$(http_code "https://discord.com/login")
fi
echo "discord_http=$dcode"
discord_http_ok=no
case "$dcode" in
	2*|3*) discord_http_ok=yes ;;
esac
echo "discord_http_ok=$discord_http_ok"

# Network OK if HTTP works OR (DNS healthy Cloudflare + not poison)
# Do NOT mark NETWORK_DISCORD on curl 000 alone when DNS is clean CF.
discord_net=no
if [ "$discord_http_ok" = "yes" ]; then
	discord_net=yes
elif [ "$discord_dns_ok" = "yes" ] && [ "$discord_poison" = "no" ]; then
	discord_net=yes
	echo "discord_net_note=dns_ok_curl_flaky"
fi
echo "discord_net_ok=$discord_net"

# --- GitHub (Vencord) ---
gcode=$(http_code "https://api.github.com")
echo "github_api_http=$gcode"
gcode2=$(http_code "https://github.com")
echo "github_web_http=$gcode2"
github_net=no
case "$gcode" in
	2*|3*) github_net=yes ;;
esac
case "$gcode2" in
	2*|3*) github_net=yes ;;
esac
echo "github_net_ok=$github_net"

gip=""
if command -v dig >/dev/null 2>&1; then
	gip=$(dig +short +time=3 +tries=2 api.github.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
fi
echo "github_api_dns_ip=${gip:-?}"

# --- Discord.app / Vencord ---
if [ -d "/Applications/Discord.app" ]; then
	echo "discord_app=yes"
	echo "discord_app_path=/Applications/Discord.app"
	discord_app=yes
	res="/Applications/Discord.app/Contents/Resources"
	if [ -f "$res/app.asar" ]; then
		echo "app_asar=yes"
		if [ -f "$res/app.asar.orig" ] || [ -f "$res/_app.asar" ] || ls "$res" 2>/dev/null | grep -qi vencord; then
			echo "vencord_asar_hint=yes"
			vencord_hint=yes
		else
			echo "vencord_asar_hint=maybe"
			vencord_hint=maybe
		fi
	else
		echo "app_asar=no"
		vencord_hint=unknown
	fi
else
	echo "discord_app=no"
	discord_app=no
	vencord_hint=no
fi

CU=$(stat -f '%Su' /dev/console 2>/dev/null)
vencord_support=no
if [ -d "$HOME/Library/Application Support/Vencord" ]; then
	vencord_support=yes
elif [ -n "$CU" ] && [ -d "/Users/$CU/Library/Application Support/Vencord" ]; then
	vencord_support=yes
fi
echo "vencord_support=$vencord_support"

hl="$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
if [ -f "$hl" ] && grep -q 'api.github.com' "$hl" 2>/dev/null; then
	echo "hostlist_github_api=yes"
else
	echo "hostlist_github_api=no"
fi

# --- ROOT_CAUSE priority ---
# 1) no app  2) real DNS poison  3) GitHub down (Vencord needs it)
# 4) Vencord present + network OK → patch  5) network really broken
if [ "$discord_app" = "no" ]; then
	echo "ROOT_CAUSE=DISCORD_MISSING"
	echo "HINT=discord.com'dan resmi Discord.app kur; sonra Vencord Installer ile ayni app'e patch."
elif [ "$discord_poison" = "yes" ]; then
	echo "ROOT_CAUSE=NETWORK_DISCORD"
	echo "HINT=DNS zehirli. Menü: Aç + DNS düzelt (bu ağ) + Bu ağı yeniden ayarla."
elif [ "$github_net" = "no" ] && [ "$discord_net" = "yes" ]; then
	echo "ROOT_CAUSE=GITHUB_NETWORK"
	echo "HINT=Discord DNS OK ama GitHub yok — Vencord buna takilir. Menü: Bu ağı yeniden ayarla. Sonra Discord.app'i ac."
elif [ "$discord_net" = "no" ] && [ "$discord_poison" = "no" ] && [ "$discord_dns_ok" = "no" ]; then
	echo "ROOT_CAUSE=NETWORK_DISCORD"
	echo "HINT=Discord DNS/HTTP kotu. Menü: Aç + Bu ağı yeniden ayarla + DNS düzelt."
elif [ "$vencord_support" = "yes" ] || [ "$vencord_hint" = "yes" ]; then
	echo "ROOT_CAUSE=VENCORD_PATCH"
	echo "HINT=Ag genelde OK (DNS temiz, GitHub erisilebilir). Vencord patch: https://vencord.dev/download/ → ayni Discord.app → Repair/Update. Ayrı client gerekmez."
elif [ "$discord_net" = "yes" ] && [ "$github_net" = "yes" ]; then
	echo "ROOT_CAUSE=OK_OR_UNKNOWN_CLIENT"
	echo "HINT=Ag OK. App acilmiyorsa Vencord Repair (Discord.app uzerinde)."
else
	echo "ROOT_CAUSE=UNKNOWN"
	echo "HINT=Zapret Acik + Bu ağı yeniden ayarla; sonra discord-diag tekrar."
fi
exit 0
