#!/bin/sh
# Post-install verification (run after system-install.sh)
set -e
. "$(dirname "$0")/lib.sh"

echo "=== Zapret dogrulama ==="
echo ""

echo "-- Motor --"
if [ -d "$ZAPRET_OPT" ]; then
	echo "OK /opt/zapret mevcut"
else
	echo "EKSIK: /opt/zapret — sudo system-install.sh veya Zapret Kurulum.app"
fi

if [ -x /usr/local/bin/zapret-ctl ]; then
	echo "OK zapret-ctl"
else
	echo "EKSIK: /usr/local/bin/zapret-ctl"
fi

if [ -f /etc/sudoers.d/zapret-toggle ]; then
	echo "OK sudoers.d/zapret-toggle"
else
	echo "EKSIK: sudoers (system-install ile gelir)"
fi

echo ""
echo "-- Durum --"
if [ -x /usr/local/bin/zapret-ctl ]; then
	sudo -n /usr/local/bin/zapret-ctl status 2>&1 || "$ZAPRET_HOME/scripts/zapret-status.sh" 2>&1 || true
else
	"$ZAPRET_HOME/scripts/zapret-status.sh" 2>&1 || true
fi

echo ""
echo "-- Surecler --"
pgrep -lf tpws 2>/dev/null || echo "tpws yok"

echo ""
echo "-- Menubar --"
if [ -d /Applications/ZapretToggle.app ]; then
	echo "OK /Applications/ZapretToggle.app"
	pgrep -lf ZapretToggle >/dev/null && echo "OK ZapretToggle calisiyor" || echo "Menubar kapali — open /Applications/ZapretToggle.app"
else
	echo "Menubar /Applications'ta yok — scripts/install-menubar.sh"
fi

echo ""
echo "-- WARP --"
if command -v warp-cli >/dev/null 2>&1; then
	warp-cli status 2>&1 | head -3 || true
elif [ -x "/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli" ]; then
	"/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli" status 2>&1 | head -3 || true
else
	echo "warp-cli yok"
fi

echo ""
echo "-- Tailscale --"
if command -v tailscale >/dev/null 2>&1; then
	tailscale status 2>&1 | head -6 || true
else
	echo "tailscale CLI yok"
fi

echo ""
echo "-- PF yedek --"
ls -la "$ZAPRET_HOME/backups"/pf.conf* 2>/dev/null | tail -5 || true

echo ""
echo "=== Bitti ==="
