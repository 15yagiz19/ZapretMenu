#!/bin/sh
# Print network identity lines for profile keying.
# Usage: zapret-net-id.sh
# Output:
#   ssid=...
#   gateway=...
#   iface=Wi-Fi|Ethernet|Unknown
#   id=<12 hex of sha256>
#   display=<human name>

set +e

SUPPORT="/Library/Application Support/Zapret"
ssid=""
iface="Unknown"
gateway=""

# Default route gateway + interface
ROUTE=$(route -n get default 2>/dev/null)
gateway=$(printf '%s\n' "$ROUTE" | awk '/gateway:/{print $2; exit}')
ifname=$(printf '%s\n' "$ROUTE" | awk '/interface:/{print $2; exit}')

# Map BSD if to networksetup service
if [ -n "$ifname" ]; then
	case "$ifname" in
		en0|en1|en2|en3|en4|en5|en6|en7|en8|en9)
			# Prefer Wi-Fi label if airport
			AIR=$(networksetup -getairportnetwork "$ifname" 2>/dev/null)
			case "$AIR" in
				You\ are\ not\ associated*)
					# wired-ish
					iface="Ethernet"
					ssid=""
					;;
				Current\ Wi-Fi\ Network:*)
					iface="Wi-Fi"
					ssid=$(printf '%s\n' "$AIR" | sed 's/^Current Wi-Fi Network: //')
					;;
				*)
					# try generic
					if networksetup -listallhardwareports 2>/dev/null | awk -v i="$ifname" '
						/Hardware Port: Wi-Fi/{w=1} /Hardware Port:/{if(!/Wi-Fi/)w=0} /Device:/{if(w && $2==i) f=1} END{exit !f}
					'; then
						iface="Wi-Fi"
						AIR=$(networksetup -getairportnetwork "$ifname" 2>/dev/null)
						ssid=$(printf '%s\n' "$AIR" | sed 's/^Current Wi-Fi Network: //')
					else
						iface="Ethernet"
					fi
					;;
			esac
			;;
		utun*|ipsec*|ppp*)
			iface="VPN"
			ssid="vpn-$ifname"
			;;
		*)
			iface="$ifname"
			;;
	esac
fi

# Fallback SSID via system_profiler / airport (best effort)
if [ -z "$ssid" ] && [ "$iface" = "Wi-Fi" ]; then
	ssid=$(networksetup -getairportnetwork en0 2>/dev/null | sed 's/^Current Wi-Fi Network: //')
	case "$ssid" in
		You\ are\ not\ associated*|"") ssid="" ;;
	esac
fi

[ -n "$gateway" ] || gateway="0.0.0.0"
[ -n "$ssid" ] || ssid="unknown"
display="$ssid"
if [ "$ssid" = "unknown" ] && [ -n "$ifname" ]; then
	display="$iface/$ifname"
fi

raw="${ssid}|${gateway}|${iface}"
# Prefer shasum; fallback md5
if command -v shasum >/dev/null 2>&1; then
	id=$(printf '%s' "$raw" | shasum -a 256 | awk '{print substr($1,1,16)}')
elif command -v md5 >/dev/null 2>&1; then
	id=$(printf '%s' "$raw" | md5 | awk '{print substr($1,1,16)}')
else
	id=$(printf '%s' "$raw" | cksum | awk '{print $1}')
fi

echo "ssid=$ssid"
echo "gateway=$gateway"
echo "iface=$iface"
echo "ifname=${ifname:-}"
echo "id=$id"
echo "display=$display"
exit 0
