#!/bin/sh
# Diagnose Discord.app + Vencord vs Zapret network (read-only).
# No Vesktop / alternate clients — official Discord.app only.
# Output key=value lines + ROOT_CAUSE=...
set +e

SUPPORT="/Library/Application Support/Zapret"
ZAPRET_OPT="/opt/zapret"

echo "=== Zapret Discord/Vencord diag ==="
echo "goal=Discord.app+Vencord (no alternate client)"

# Zapret state
desired=on
if [ -f "$SUPPORT/desired-state" ]; then
	desired=$(tr -d ' \t\r\n' < "$SUPPORT/desired-state" | tr '[:upper:]' '[:lower:]')
fi
echo "desired=$desired"
if pgrep -xq tpws 2>/dev/null; then
	echo "tpws=yes"
	tpws=yes
else
	echo "tpws=no"
	tpws=no
fi

# Discord DNS
dip=""
if command -v dig >/dev/null 2>&1; then
	dip=$(dig +short +time=2 +tries=1 discord.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
fi
echo "discord_dns_ip=${dip:-?}"
discord_poison=no
case "$dip" in
	195.175.254.*) discord_poison=yes ;;
esac
echo "discord_dns_poison=$discord_poison"

# Discord HTTPS (HEAD can fail on some paths; fall back to GET range)
dcode=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -I "https://discord.com" 2>/dev/null || echo 000)
case "$dcode" in
	000|4*|5*)
		dcode=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 12 "https://discord.com" 2>/dev/null || echo 000)
		;;
esac
echo "discord_http=$dcode"
discord_net=no
case "$dcode" in
	2*|3*) discord_net=yes ;;
esac
echo "discord_net_ok=$discord_net"

# GitHub (critical for Vencord)
gcode=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -I "https://api.github.com" 2>/dev/null || echo 000)
echo "github_api_http=$gcode"
gcode2=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -I "https://github.com" 2>/dev/null || echo 000)
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
	gip=$(dig +short +time=2 +tries=1 api.github.com A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
fi
echo "github_api_dns_ip=${gip:-?}"

# Discord.app
if [ -d "/Applications/Discord.app" ]; then
	echo "discord_app=yes"
	echo "discord_app_path=/Applications/Discord.app"
	discord_app=yes
	res="/Applications/Discord.app/Contents/Resources"
	if [ -f "$res/app.asar" ]; then
		echo "app_asar=yes"
		# Vencord often keeps backup
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

# Vencord support dir
if [ -d "$HOME/Library/Application Support/Vencord" ] || [ -d "/Users/$(stat -f '%Su' /dev/console 2>/dev/null)/Library/Application Support/Vencord" ]; then
	echo "vencord_support=yes"
	vencord_support=yes
else
	# try console user home when run as root
	CU=$(stat -f '%Su' /dev/console 2>/dev/null)
	if [ -n "$CU" ] && [ -d "/Users/$CU/Library/Application Support/Vencord" ]; then
		echo "vencord_support=yes"
		vencord_support=yes
	else
		echo "vencord_support=no"
		vencord_support=no
	fi
fi

# Hostlist has api.github.com?
hl="$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
if [ -f "$hl" ] && grep -q 'api.github.com' "$hl" 2>/dev/null; then
	echo "hostlist_github_api=yes"
else
	echo "hostlist_github_api=no"
fi

# ROOT_CAUSE
if [ "$discord_app" = "no" ]; then
	echo "ROOT_CAUSE=DISCORD_MISSING"
	echo "HINT=Install official Discord.app from discord.com then Vencord Installer patch (same app)."
elif [ "$discord_poison" = "yes" ] || [ "$discord_net" = "no" ]; then
	echo "ROOT_CAUSE=NETWORK_DISCORD"
	echo "HINT=Menü: Aç + Bu ağı yeniden ayarla + DNS düzelt (bu ağ)."
elif [ "$github_net" = "no" ]; then
	echo "ROOT_CAUSE=GITHUB_NETWORK"
	echo "HINT=Vencord needs GitHub. Menü: Bu ağı yeniden ayarla. hostlist must include api.github.com. Then open Discord.app again."
elif [ "$vencord_support" = "yes" ] || [ "$vencord_hint" = "yes" ] || [ "$vencord_hint" = "maybe" ]; then
	echo "ROOT_CAUSE=VENCORD_PATCH"
	echo "HINT=Network OK. Repair Vencord ON THE SAME Discord.app: https://vencord.dev/download/ → Repair/Update (not a different client)."
else
	if [ "$discord_net" = "yes" ] && [ "$github_net" = "yes" ]; then
		echo "ROOT_CAUSE=OK_OR_UNKNOWN_CLIENT"
		echo "HINT=Network looks fine. If app still fails: Vencord Installer Repair on Discord.app."
	else
		echo "ROOT_CAUSE=UNKNOWN"
		echo "HINT=Check Zapret open + net-probe."
	fi
fi
exit 0
