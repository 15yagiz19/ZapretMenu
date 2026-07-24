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

# Package version (set by package-dmg / self-update; fallback)
ZAPRET_VERSION="${ZAPRET_VERSION:-}"
if [ -z "$ZAPRET_VERSION" ] && [ -f "$ZAPRET_HOME/VERSION" ]; then
	ZAPRET_VERSION=$(tr -d ' \t\r\n' < "$ZAPRET_HOME/VERSION")
fi
if [ -z "$ZAPRET_VERSION" ] && [ -f "$SCRIPTS_DIR/../VERSION" ]; then
	ZAPRET_VERSION=$(tr -d ' \t\r\n' < "$SCRIPTS_DIR/../VERSION")
fi
[ -n "$ZAPRET_VERSION" ] || ZAPRET_VERSION="1.1.0"

# Preserve user hostlist if already customized under Application Support
USER_HOSTLIST_SAVED=""
if [ -f "$SUPPORT_DIR/config/zapret-hosts-user.txt" ]; then
	USER_HOSTLIST_SAVED=$(mktemp)
	cp "$SUPPORT_DIR/config/zapret-hosts-user.txt" "$USER_HOSTLIST_SAVED"
	echo "Kullanici hostlist korunacak: $SUPPORT_DIR/config/zapret-hosts-user.txt"
fi

# 1) Support dir + PF backup
mkdir -p "$SUPPORT_DIR/backups" "$SUPPORT_DIR/config" "$SUPPORT_DIR/logs" "$SUPPORT_DIR/cache"
TS=$(date +%Y%m%d-%H%M%S)
if [ -f /etc/pf.conf ]; then
	cp -a /etc/pf.conf "$SUPPORT_DIR/backups/pf.conf.pre-install.$TS"
	cp -a /etc/pf.conf "/etc/pf.conf.bak.zapret.$TS"
	echo "PF yedek: /etc/pf.conf.bak.zapret.$TS"
fi

# 2) Clean stop + unload ALL zapret launchd jobs (KeepAlive + boot + netwatch + legacy)
echo "Eski servisler durduruluyor..."
for lbl in system/zapret-tpws system/zapret-boot system/zapret-netwatch system/zapret system/zapret-watchdog; do
	launchctl bootout "$lbl" 2>/dev/null || true
done
if [ -x "$ZAPRET_OPT/init.d/macos/zapret" ]; then
	"$ZAPRET_OPT/init.d/macos/zapret" stop 2>/dev/null || true
	"$ZAPRET_OPT/init.d/macos/zapret" stop-fw 2>/dev/null || true
	"$ZAPRET_OPT/init.d/macos/zapret" stop-daemons 2>/dev/null || true
fi
if [ -x "$ZAPRET_OPT/local-tools/zapret-stop.sh" ]; then
	"$ZAPRET_OPT/local-tools/zapret-stop.sh" 2>/dev/null || true
fi
pkill -x tpws 2>/dev/null || true
rm -f /var/run/tpws1.pid 2>/dev/null || true
sleep 0.5

# 3) Clean reinstall: single backup, remove old prev/bak pile
ZAPRET_CLEAN_REINSTALL="${ZAPRET_CLEAN_REINSTALL:-1}"
BACKUP_DIR=""
if [ -d "$ZAPRET_OPT" ]; then
	if [ "$ZAPRET_CLEAN_REINSTALL" = "1" ]; then
		BACKUP_DIR="/opt/zapret.bak.$TS"
		mv "$ZAPRET_OPT" "$BACKUP_DIR"
		echo "Eski kurulum yedeklendi: $BACKUP_DIR"
		# Keep only the newest bak + remove legacy prev.* piles
		ls -1d /opt/zapret.prev.* 2>/dev/null | while read -r d; do
			rm -rf "$d"
			echo "Silindi (eski prev): $d"
		done
		# Keep only this backup + at most one previous bak
		ls -1dt /opt/zapret.bak.* 2>/dev/null | tail -n +3 | while read -r d; do
			rm -rf "$d"
			echo "Silindi (eski bak): $d"
		done
	else
		mv "$ZAPRET_OPT" "/opt/zapret.prev.$TS"
		echo "Eski kurulum tasindi: /opt/zapret.prev.$TS"
	fi
fi

echo "Kopyalaniyor: motor -> /opt/zapret (temiz kurulum)"
mkdir -p "$ZAPRET_OPT"
if command -v rsync >/dev/null 2>&1; then
	rsync -a --exclude '.git' --exclude '.github' "$ZAPRET_UPSTREAM/" "$ZAPRET_OPT/"
else
	cp -R "$ZAPRET_UPSTREAM/." "$ZAPRET_OPT/"
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

# Critical: macOS control scripts must exist after copy
if [ ! -x "$ZAPRET_OPT/init.d/macos/zapret" ]; then
	echo "HATA: /opt/zapret/init.d/macos/zapret yok."
	echo "Paket bozuk olabilir (init.d kopyalanmamis). Yeni DMG ile tekrar kurun."
	if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
		echo "Geri yukleniyor: $BACKUP_DIR"
		rm -rf "$ZAPRET_OPT"
		mv "$BACKUP_DIR" "$ZAPRET_OPT"
	fi
	exit 1
fi
chmod 755 "$ZAPRET_OPT/init.d/macos/zapret" 2>/dev/null || true
find "$ZAPRET_OPT/init.d" -type f \( -name 'zapret' -o -name '*.sh' \) -exec chmod 755 {} \; 2>/dev/null || true
find "$ZAPRET_OPT/ipset" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true
find "$ZAPRET_OPT/tpws" -type f -name 'tpws' -exec chmod 755 {} \; 2>/dev/null || true
find "$ZAPRET_OPT/binaries" -type f -exec chmod 755 {} \; 2>/dev/null || true

# 4) Config + hostlist + custom.d (preserve user hostlist)
cp "$CONFIG_SRC" "$ZAPRET_OPT/config"
cp "$CONFIG_SRC" "$ZAPRET_OPT/config.default.macos" 2>/dev/null || true
mkdir -p "$ZAPRET_OPT/ipset" "$ZAPRET_OPT/tmp"

if [ -n "$USER_HOSTLIST_SAVED" ] && [ -f "$USER_HOSTLIST_SAVED" ]; then
	cp "$USER_HOSTLIST_SAVED" "$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
	cp "$USER_HOSTLIST_SAVED" "$SUPPORT_DIR/config/zapret-hosts-user.txt"
	rm -f "$USER_HOSTLIST_SAVED"
	echo "Kullanici hostlist geri yuklendi."
else
	cp "$HOSTLIST_SRC" "$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
	cp "$HOSTLIST_SRC" "$SUPPORT_DIR/config/zapret-hosts-user.txt"
fi
touch "$ZAPRET_OPT/ipset/zapret-hosts-user-exclude.txt"
touch "$ZAPRET_OPT/ipset/zapret-ip-exclude.txt"
cp "$CONFIG_SRC" "$SUPPORT_DIR/config/config.macos-hostlist"

if [ -d "$ZAPRET_HOME/config/custom.d" ]; then
	mkdir -p "$ZAPRET_OPT/init.d/macos/custom.d" "$SUPPORT_DIR/config/custom.d"
	cp -f "$ZAPRET_HOME/config/custom.d"/* "$ZAPRET_OPT/init.d/macos/custom.d/" 2>/dev/null || true
	cp -f "$ZAPRET_HOME/config/custom.d"/* "$SUPPORT_DIR/config/custom.d/" 2>/dev/null || true
	chmod 644 "$ZAPRET_OPT/init.d/macos/custom.d"/* 2>/dev/null || true
fi

# 5) local-tools (portable scripts + KeepAlive + self-update)
mkdir -p "$LOCAL_TOOLS"
for f in lib.sh zapret-ctl zapret-start.sh zapret-stop.sh zapret-status.sh \
	zapret-update-lists.sh zapret-update-engine.sh zapret-rollback-engine.sh \
	fix-dns-turkey.sh zapret-uninstall.sh verify.sh \
	zapret-tpws-run.sh zapret-boot.sh \
	zapret-self-update.sh zapret-check-update.sh \
	zapret-profile-lib.sh zapret-net-id.sh zapret-net-status.sh \
	zapret-apply-profile.sh zapret-probe-network.sh zapret-netwatch.sh; do
	if [ -f "$SCRIPTS_DIR/$f" ]; then
		cp "$SCRIPTS_DIR/$f" "$LOCAL_TOOLS/$f"
	fi
done
for f in zapret-tpws.plist zapret-boot.plist zapret-netwatch.plist; do
	if [ -f "$SCRIPTS_DIR/$f" ]; then
		cp "$SCRIPTS_DIR/$f" "$LOCAL_TOOLS/$f"
	fi
done
# Strategy presets for per-network profiles
if [ -d "$ZAPRET_HOME/config/strategies" ]; then
	mkdir -p "$LOCAL_TOOLS/strategies"
	cp -f "$ZAPRET_HOME/config/strategies/"*.tpws "$LOCAL_TOOLS/strategies/" 2>/dev/null || true
elif [ -d "$SCRIPTS_DIR/../config/strategies" ]; then
	mkdir -p "$LOCAL_TOOLS/strategies"
	cp -f "$SCRIPTS_DIR/../config/strategies/"*.tpws "$LOCAL_TOOLS/strategies/" 2>/dev/null || true
fi
chmod 755 "$LOCAL_TOOLS"/*.sh "$LOCAL_TOOLS"/zapret-ctl 2>/dev/null || true
chmod 644 "$LOCAL_TOOLS"/*.plist 2>/dev/null || true
chmod 644 "$LOCAL_TOOLS/strategies/"* 2>/dev/null || true
mkdir -p "$SUPPORT_DIR/profiles"

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

# 7) launchd: KeepAlive tpws + boot loader (replace legacy one-shot + 30s watchdog)
mkdir -p "$SUPPORT_DIR/logs"
# Remove legacy jobs if present
launchctl bootout system/zapret 2>/dev/null || true
launchctl bootout system/zapret-watchdog 2>/dev/null || true
rm -f /Library/LaunchDaemons/zapret.plist /Library/LaunchDaemons/zapret-watchdog.plist

if [ -f "$LOCAL_TOOLS/zapret-tpws.plist" ]; then
	cp "$LOCAL_TOOLS/zapret-tpws.plist" /Library/LaunchDaemons/zapret-tpws.plist
	chmod 644 /Library/LaunchDaemons/zapret-tpws.plist
	chown root:wheel /Library/LaunchDaemons/zapret-tpws.plist
	echo "launchd zapret-tpws KeepAlive kuruldu."
fi
if [ -f "$LOCAL_TOOLS/zapret-boot.plist" ]; then
	cp "$LOCAL_TOOLS/zapret-boot.plist" /Library/LaunchDaemons/zapret-boot.plist
	chmod 644 /Library/LaunchDaemons/zapret-boot.plist
	chown root:wheel /Library/LaunchDaemons/zapret-boot.plist
	echo "launchd zapret-boot kuruldu."
fi
if [ -f "$LOCAL_TOOLS/zapret-netwatch.plist" ]; then
	cp "$LOCAL_TOOLS/zapret-netwatch.plist" /Library/LaunchDaemons/zapret-netwatch.plist
	chmod 644 /Library/LaunchDaemons/zapret-netwatch.plist
	chown root:wheel /Library/LaunchDaemons/zapret-netwatch.plist
	echo "launchd zapret-netwatch kuruldu (15sn ag izleme)."
fi

# desired-state default on
printf 'on\n' > "$SUPPORT_DIR/desired-state"
chmod 644 "$SUPPORT_DIR/desired-state"
mkdir -p "$SUPPORT_DIR/profiles"

# 8) zapret-ctl + sudoers (target user, not hardcoded)
# IMPORTANT: ctl must live under /opt/zapret/local-tools (no home path)
mkdir -p /usr/local/bin
# Embed SCRIPTS_DIR resolution: always prefer /opt/zapret/local-tools when installed
cp "$LOCAL_TOOLS/zapret-ctl" "$CTL_PATH"
# Rewrite any residual absolute home path in ctl is avoided by portable ctl
chmod 755 "$CTL_PATH"
chown root:wheel "$CTL_PATH"
# Also keep ctl inside local-tools for direct use
cp "$LOCAL_TOOLS/zapret-ctl" "$LOCAL_TOOLS/zapret-ctl" 2>/dev/null || true

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

# 10) Start: PF + KeepAlive foreground tpws (no --daemon)
echo "Zapret baslatiliyor (KeepAlive)..."
printf 'on\n' > "$SUPPORT_DIR/desired-state"
# Kill any old daemonized tpws
pkill -x tpws 2>/dev/null || true
rm -f /var/run/tpws1.pid 2>/dev/null || true
sleep 0.5

if [ -x "$ZAPRET_OPT/init.d/macos/zapret" ]; then
	"$ZAPRET_OPT/init.d/macos/zapret" start-fw 2>/dev/null || true
fi

if [ -f /Library/LaunchDaemons/zapret-tpws.plist ]; then
	launchctl bootout system/zapret-tpws 2>/dev/null || true
	launchctl bootstrap system /Library/LaunchDaemons/zapret-tpws.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/zapret-tpws.plist 2>/dev/null || true
	echo "KeepAlive tpws yuklendi."
fi
if [ -f /Library/LaunchDaemons/zapret-boot.plist ]; then
	launchctl bootout system/zapret-boot 2>/dev/null || true
	launchctl bootstrap system /Library/LaunchDaemons/zapret-boot.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/zapret-boot.plist 2>/dev/null || true
fi
if [ -f /Library/LaunchDaemons/zapret-netwatch.plist ]; then
	launchctl bootout system/zapret-netwatch 2>/dev/null || true
	launchctl bootstrap system /Library/LaunchDaemons/zapret-netwatch.plist 2>/dev/null || \
	launchctl load -w /Library/LaunchDaemons/zapret-netwatch.plist 2>/dev/null || true
	echo "netwatch yuklendi (Wi-Fi degisince otomatik profil)."
fi

sleep 2
if pgrep -xq tpws; then
	echo "OK: tpws calisiyor (KeepAlive)."
else
	echo "UYARI: tpws henuz gorunmuyor — status / logs kontrol edin."
	echo "  $SUPPORT_DIR/logs/tpws-stderr.log"
fi

# Initial network profile probe (best effort, non-fatal)
if [ -x "$LOCAL_TOOLS/zapret-probe-network.sh" ]; then
	echo "Ag profili hazirlaniyor (probe)..."
	"$LOCAL_TOOLS/zapret-probe-network.sh" 2>/dev/null || true
fi

# 11) DNS fix for Turkey (Discord poison via router DNS)
# Skip during silent self-update unless ZAPRET_FIX_DNS=1
if [ "${ZAPRET_FIX_DNS:-1}" = "1" ]; then
	echo "DNS duzeltiliyor (Discord icin)..."
	if [ -x "$LOCAL_TOOLS/fix-dns-turkey.sh" ]; then
		if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "root" ]; then
			sudo -u "$USER_NAME" "$LOCAL_TOOLS/fix-dns-turkey.sh" 2>/dev/null || "$LOCAL_TOOLS/fix-dns-turkey.sh" || true
		else
			"$LOCAL_TOOLS/fix-dns-turkey.sh" || true
		fi
	fi
fi

# 12) Write installed version + success marker
printf '%s\n' "$ZAPRET_VERSION" > "$SUPPORT_DIR/version"
chmod 644 "$SUPPORT_DIR/version"
# On success with clean reinstall, drop older backups beyond the newest one
if [ "$ZAPRET_CLEAN_REINSTALL" = "1" ] && [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
	# Keep the one we just made; remove older baks beyond 1 previous
	ls -1dt /opt/zapret.bak.* 2>/dev/null | tail -n +3 | while read -r d; do
		rm -rf "$d"
	done
fi

echo ""
echo "=== Kurulum tamam ==="
echo "  Surum:      $ZAPRET_VERSION"
echo "  Motor:      $ZAPRET_OPT"
echo "  Scriptler:  $LOCAL_TOOLS"
echo "  Destek:     $SUPPORT_DIR"
echo "  Config:     $ZAPRET_OPT/config (hostlist)"
echo "  Hostlist:   $ZAPRET_OPT/ipset/zapret-hosts-user.txt"
echo "  ctl:        $CTL_PATH"
echo "  sudoers:    $SUDOERS_FILE ($USER_NAME)"
echo "  PF yedek:   $SUPPORT_DIR/backups/"
echo "  desired:    $SUPPORT_DIR/desired-state"
echo "  KeepAlive:  /Library/LaunchDaemons/zapret-tpws.plist"
echo "  boot:       /Library/LaunchDaemons/zapret-boot.plist"
if [ -n "$BACKUP_DIR" ]; then
	echo "  Yedek:      $BACKUP_DIR"
fi
echo ""
echo "Test: sudo $CTL_PATH status"
echo "      sudo $CTL_PATH check-update"
echo "      sudo $CTL_PATH self-update"
echo "INSTALL_OK"
exit 0
