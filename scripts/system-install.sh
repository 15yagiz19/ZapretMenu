#!/bin/sh
# Non-interactive macOS install of bol-van/zapret (hostlist + tpws + PF + launchd)
# Portable: detects package root from script location; target user from SUDO_USER.
#
# Usage:
#   sudo ./system-install.sh
#   sudo ZAPRET_HOME=... ZAPRET_UPSTREAM=... ./system-install.sh
set -e

SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# Dev layout: <repo>/scripts  |  DMG payload: <payload>/scripts  |  live: /opt/zapret/local-tools
case "$SCRIPTS_DIR" in
	*/scripts)
		PKG_ROOT="$(CDPATH= cd -- "$SCRIPTS_DIR/.." && pwd)"
		;;
	*)
		PKG_ROOT="$(CDPATH= cd -- "$SCRIPTS_DIR/.." && pwd)"
		;;
esac

ZAPRET_HOME="${ZAPRET_HOME:-$PKG_ROOT}"
ZAPRET_UPSTREAM="${ZAPRET_UPSTREAM:-$ZAPRET_HOME/upstream}"
# Payload layout uses bundled/ for prebuilt engine tree
if [ ! -d "$ZAPRET_UPSTREAM" ] && [ -d "$ZAPRET_HOME/bundled" ]; then
	ZAPRET_UPSTREAM="$ZAPRET_HOME/bundled"
fi
ZAPRET_OPT="/opt/zapret"
SUPPORT_DIR="/Library/Application Support/Zapret"
USER_NAME="${SUDO_USER:-$(id -un)}"
# When run as root via AppleScript, SUDO_USER may be empty — prefer console user
if [ "$USER_NAME" = "root" ] || [ -z "$USER_NAME" ]; then
	USER_NAME=$(stat -f '%Su' /dev/console 2>/dev/null || echo "")
fi
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
	USER_NAME=$(logname 2>/dev/null || true)
fi
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
	echo "HATA: hedef kullanici belirlenemedi (SUDO_USER / console)."
	exit 1
fi

CONFIG_SRC="${CONFIG_SRC:-$ZAPRET_HOME/config/config.macos-hostlist}"
HOSTLIST_SRC="${HOSTLIST_SRC:-$ZAPRET_HOME/config/zapret-hosts-user.txt}"
SUDOERS_FILE="/etc/sudoers.d/zapret-toggle"
CTL_PATH="/usr/local/bin/zapret-ctl"
LOCAL_TOOLS="$ZAPRET_OPT/local-tools"

if [ "$(id -u)" -ne 0 ]; then
	echo "Root gerekli: sudo $0"
	exit 1
fi

echo "=== Zapret sistem kurulumu (macOS hostlist) ==="
echo "Kaynak:  $ZAPRET_UPSTREAM"
echo "Hedef:   $ZAPRET_OPT"
echo "Kullanici: $USER_NAME"

if [ ! -d "$ZAPRET_UPSTREAM" ]; then
	echo "HATA: motor kaynagi yok: $ZAPRET_UPSTREAM"
	echo "Once: git clone https://github.com/bol-van/zapret.git ve make mac"
	exit 1
fi

if [ ! -x "$ZAPRET_UPSTREAM/tpws/tpws" ] && [ ! -x "$ZAPRET_UPSTREAM/binaries/my/tpws" ]; then
	echo "HATA: tpws binary yok. Once: cd $ZAPRET_UPSTREAM && make mac"
	exit 1
fi

if [ ! -f "$CONFIG_SRC" ] || [ ! -f "$HOSTLIST_SRC" ]; then
	echo "HATA: config veya hostlist eksik:"
	echo "  $CONFIG_SRC"
	echo "  $HOSTLIST_SRC"
	exit 1
fi

# 1) Support dir + PF backup
mkdir -p "$SUPPORT_DIR/backups" "$SUPPORT_DIR/config" "$SUPPORT_DIR/logs"
TS=$(date +%Y%m%d-%H%M%S)
if [ -f /etc/pf.conf ]; then
	cp -a /etc/pf.conf "$SUPPORT_DIR/backups/pf.conf.pre-install.$TS"
	cp -a /etc/pf.conf "/etc/pf.conf.bak.zapret.$TS"
	echo "PF yedek: /etc/pf.conf.bak.zapret.$TS"
fi

# 2) Stop existing
if [ -x "$ZAPRET_OPT/init.d/macos/zapret" ]; then
	"$ZAPRET_OPT/init.d/macos/zapret" stop 2>/dev/null || true
fi
pkill -x tpws 2>/dev/null || true
launchctl bootout system/zapret 2>/dev/null || true

# 3) Install tree to /opt/zapret
if [ -d "$ZAPRET_OPT" ]; then
	mv "$ZAPRET_OPT" "/opt/zapret.prev.$TS"
	echo "Eski kurulum tasindi: /opt/zapret.prev.$TS"
fi

echo "Kopyalaniyor: motor -> /opt/zapret"
mkdir -p "$ZAPRET_OPT"
if command -v rsync >/dev/null 2>&1; then
	rsync -a --exclude '.git' --exclude '.github' "$ZAPRET_UPSTREAM/" "$ZAPRET_OPT/"
else
	cp -R "$ZAPRET_UPSTREAM" "$ZAPRET_OPT"
	rm -rf "$ZAPRET_OPT/.git" "$ZAPRET_OPT/.github" 2>/dev/null || true
fi

# Optional: keep a source tree for engine updates (git) if present
if [ -d "$ZAPRET_UPSTREAM/.git" ]; then
	mkdir -p "$ZAPRET_OPT/src"
	if command -v rsync >/dev/null 2>&1; then
		rsync -a "$ZAPRET_UPSTREAM/" "$ZAPRET_OPT/src/"
	else
		cp -R "$ZAPRET_UPSTREAM/." "$ZAPRET_OPT/src/"
	fi
fi

# Ensure binaries present and linked
if [ -x "$ZAPRET_OPT/binaries/my/tpws" ]; then
	mkdir -p "$ZAPRET_OPT/tpws" "$ZAPRET_OPT/ip2net" "$ZAPRET_OPT/mdig"
	ln -sfn ../binaries/my/tpws "$ZAPRET_OPT/tpws/tpws"
	ln -sfn ../binaries/my/ip2net "$ZAPRET_OPT/ip2net/ip2net"
	ln -sfn ../binaries/my/mdig "$ZAPRET_OPT/mdig/mdig"
fi

# 4) Config + hostlist + custom.d
cp "$CONFIG_SRC" "$ZAPRET_OPT/config"
cp "$CONFIG_SRC" "$ZAPRET_OPT/config.default.macos" 2>/dev/null || true
mkdir -p "$ZAPRET_OPT/ipset" "$ZAPRET_OPT/tmp"
cp "$HOSTLIST_SRC" "$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
touch "$ZAPRET_OPT/ipset/zapret-hosts-user-exclude.txt"
touch "$ZAPRET_OPT/ipset/zapret-ip-exclude.txt"

# Persist editable copies under Application Support
cp "$CONFIG_SRC" "$SUPPORT_DIR/config/config.macos-hostlist"
cp "$HOSTLIST_SRC" "$SUPPORT_DIR/config/zapret-hosts-user.txt"

if [ -d "$ZAPRET_HOME/config/custom.d" ]; then
	mkdir -p "$ZAPRET_OPT/init.d/macos/custom.d" "$SUPPORT_DIR/config/custom.d"
	cp -f "$ZAPRET_HOME/config/custom.d"/* "$ZAPRET_OPT/init.d/macos/custom.d/" 2>/dev/null || true
	cp -f "$ZAPRET_HOME/config/custom.d"/* "$SUPPORT_DIR/config/custom.d/" 2>/dev/null || true
	chmod 644 "$ZAPRET_OPT/init.d/macos/custom.d"/* 2>/dev/null || true
fi

# 5) local-tools (portable scripts for ctl)
mkdir -p "$LOCAL_TOOLS"
for f in lib.sh zapret-ctl zapret-start.sh zapret-stop.sh zapret-status.sh \
	zapret-update-lists.sh zapret-update-engine.sh zapret-rollback-engine.sh \
	fix-dns-turkey.sh zapret-uninstall.sh verify.sh; do
	if [ -f "$SCRIPTS_DIR/$f" ]; then
		cp "$SCRIPTS_DIR/$f" "$LOCAL_TOOLS/$f"
	fi
done
chmod 755 "$LOCAL_TOOLS"/* 2>/dev/null || true

# 6) Permissions
chown -R root:wheel "$ZAPRET_OPT"
find "$ZAPRET_OPT" -type d -exec chmod 755 {} \;
find "$ZAPRET_OPT" -type f -exec chmod 644 {} \;
find "$ZAPRET_OPT/binaries" -type f -exec chmod 755 {} \; 2>/dev/null || true
chmod 755 "$ZAPRET_OPT/init.d/macos/zapret" 2>/dev/null || true
chmod 755 "$ZAPRET_OPT/tpws/tpws" 2>/dev/null || true
chmod 755 "$ZAPRET_OPT/ip2net/ip2net" 2>/dev/null || true
chmod 755 "$ZAPRET_OPT/mdig/mdig" 2>/dev/null || true
find "$ZAPRET_OPT/ipset" -name 'get_*.sh' -exec chmod 755 {} \;
find "$ZAPRET_OPT/ipset" -name '*.sh' -exec chmod 755 {} \;
chmod 755 "$ZAPRET_OPT/install_easy.sh" "$ZAPRET_OPT/uninstall_easy.sh" 2>/dev/null || true
chmod 755 "$ZAPRET_OPT/blockcheck.sh" 2>/dev/null || true
chmod 755 "$LOCAL_TOOLS"/* 2>/dev/null || true

# Support dir: editable by install user for hostlist tweaks
chown -R "$USER_NAME:staff" "$SUPPORT_DIR" 2>/dev/null || chown -R "$USER_NAME" "$SUPPORT_DIR" 2>/dev/null || true
chmod -R u+rwX,go+rX "$SUPPORT_DIR" 2>/dev/null || true

# 7) launchd
ln -fs "$ZAPRET_OPT/init.d/macos/zapret.plist" /Library/LaunchDaemons/zapret.plist
echo "launchd plist baglandi."

# 8) zapret-ctl + sudoers (target user, not hardcoded)
mkdir -p /usr/local/bin
cp "$LOCAL_TOOLS/zapret-ctl" "$CTL_PATH"
chmod 755 "$CTL_PATH"
chown root:wheel "$CTL_PATH"

TMP_SUDOERS=$(mktemp)
cat > "$TMP_SUDOERS" <<EOF
# Zapret menubar helper — only whitelist commands via zapret-ctl
# Generated by system-install.sh — do not grant broader privileges
$USER_NAME ALL=(root) NOPASSWD: $CTL_PATH
EOF
if visudo -cf "$TMP_SUDOERS"; then
	cp "$TMP_SUDOERS" "$SUDOERS_FILE"
	chmod 440 "$SUDOERS_FILE"
	chown root:wheel "$SUDOERS_FILE"
	if visudo -cf "$SUDOERS_FILE"; then
		echo "sudoers OK: $SUDOERS_FILE ($USER_NAME)"
	else
		echo "HATA: sudoers dogrulama basarisiz — siliniyor"
		rm -f "$SUDOERS_FILE"
		exit 1
	fi
else
	echo "HATA: gecici sudoers gecersiz"
	rm -f "$TMP_SUDOERS"
	exit 1
fi
rm -f "$TMP_SUDOERS"

# 9) QUIC note
cat > "$SUPPORT_DIR/config/quic-note.txt" <<'QEOF'
QUIC (UDP/443):
macOS tpws only handles TCP. This install drops outbound UDP/443 while Zapret
is running (init.d/macos/custom.d/10-block-quic) so browsers fall back to TCP.
Tailscale uses UDP 41641, not 443 — left alone.
If you need QUIC back: remove that custom file and restart Zapret.
QEOF

# 10) Start service
echo "Zapret baslatiliyor..."
"$ZAPRET_OPT/init.d/macos/zapret" start

sleep 2
if pgrep -xq tpws; then
	echo "OK: tpws calisiyor."
else
	echo "UYARI: tpws henuz gorunmuyor — status kontrol edin."
	"$ZAPRET_OPT/init.d/macos/zapret" start || true
fi

if [ -f /Library/LaunchDaemons/zapret.plist ]; then
	launchctl bootstrap system /Library/LaunchDaemons/zapret.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/zapret.plist 2>/dev/null || true
fi

echo ""
echo "=== Kurulum tamam ==="
echo "  Motor:      $ZAPRET_OPT"
echo "  Scriptler:  $LOCAL_TOOLS"
echo "  Destek:     $SUPPORT_DIR"
echo "  Config:     $ZAPRET_OPT/config (hostlist)"
echo "  Hostlist:   $ZAPRET_OPT/ipset/zapret-hosts-user.txt"
echo "  ctl:        $CTL_PATH"
echo "  sudoers:    $SUDOERS_FILE ($USER_NAME)"
echo "  PF yedek:   $SUPPORT_DIR/backups/"
echo ""
echo "Test: sudo $CTL_PATH status"
echo "      sudo $CTL_PATH start|stop"
exit 0
