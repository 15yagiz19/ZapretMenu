#!/bin/sh
# Set Wi-Fi DNS to public resolvers so router/ISP DNS poison cannot map
# blocked domains (e.g. discord.com -> 195.175.254.2).
# MagicDNS (Tailscale) stays enabled; this only replaces the Wi-Fi upstream.
# Safe to re-run after Wi-Fi reconnect if DNS resets to Automatic/router.

set -e

SERVICE="${1:-Wi-Fi}"

echo "Wi-Fi (or '$SERVICE') DNS -> 1.1.1.1 1.0.0.1 8.8.8.8"
networksetup -setdnsservers "$SERVICE" 1.1.1.1 1.0.0.1 8.8.8.8
echo "Current:"
networksetup -getdnsservers "$SERVICE"

# Best-effort cache flush (root not required for dscacheutil)
dscacheutil -flushcache 2>/dev/null || true

echo ""
echo "Kontrol:"
IP="$(python3 -c "import socket; print(sorted({i[4][0] for i in socket.getaddrinfo('discord.com',443,socket.AF_INET)})[0])" 2>/dev/null || dig +short discord.com A | head -1)"
echo "  discord.com -> ${IP:-?}"
echo "  Beklenen: 162.159.x.x (Cloudflare). 195.175.254.2 = hâlâ zehirli DNS."
echo "  Tailscale MagicDNS açıksa kısa VDS adları çalışmaya devam eder."
