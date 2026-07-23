#!/bin/sh
# Build a distributable macOS DMG for Zapret (friend-friendly Turkish installer).
# Output: dist/Zapret-macOS.dmg (or versioned name)
set -e

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.1}"
ARCH_NOTE="universal (arm64+x86_64)"
DIST_DIR="$ROOT/dist"
STAGE="$DIST_DIR/stage"
PAYLOAD="$STAGE/payload"
DMG_NAME="Zapret-macOS"
DMG_PATH="$DIST_DIR/${DMG_NAME}.dmg"
DMG_VERSIONED="$DIST_DIR/${DMG_NAME}-v${VERSION}.dmg"
VOL_NAME="Zapret Kurulum"

echo "=== Zapret DMG paketleme ==="
echo "Kok: $ROOT"
echo "Surum: $VERSION"

# --- Preconditions ---
if [ ! -x "$ROOT/upstream/binaries/my/tpws" ] && [ ! -x "$ROOT/upstream/tpws/tpws" ]; then
	echo "tpws yok — make mac calistiriliyor..."
	(cd "$ROOT/upstream" && make mac)
fi
if [ ! -x "$ROOT/upstream/binaries/my/tpws" ] && [ ! -x "$ROOT/upstream/tpws/tpws" ]; then
	echo "HATA: tpws binary hala yok"
	exit 1
fi

chmod +x "$ROOT/menubar/build.sh" "$ROOT/scripts"/*.sh "$ROOT/scripts/zapret-ctl" 2>/dev/null || true

echo "Menubar derleniyor..."
"$ROOT/menubar/build.sh"

# --- Stage clean ---
rm -rf "$STAGE"
mkdir -p "$PAYLOAD/scripts" "$PAYLOAD/config" "$PAYLOAD/menubar" "$PAYLOAD/bundled"

# Scripts (portable)
for f in lib.sh zapret-ctl system-install.sh install-menubar.sh \
	zapret-start.sh zapret-stop.sh zapret-status.sh \
	zapret-update-lists.sh zapret-update-engine.sh zapret-rollback-engine.sh \
	fix-dns-turkey.sh zapret-uninstall.sh verify.sh; do
	cp "$ROOT/scripts/$f" "$PAYLOAD/scripts/$f"
done
chmod 755 "$PAYLOAD/scripts"/* 2>/dev/null || true

# Config
cp "$ROOT/config/config.macos-hostlist" "$PAYLOAD/config/"
cp "$ROOT/config/zapret-hosts-user.txt" "$PAYLOAD/config/"
if [ -d "$ROOT/config/custom.d" ]; then
	mkdir -p "$PAYLOAD/config/custom.d"
	cp -f "$ROOT/config/custom.d"/* "$PAYLOAD/config/custom.d/"
fi

# Menubar app (prebuilt)
cp -R "$ROOT/menubar/ZapretToggle.app" "$PAYLOAD/menubar/"
# Also keep sources for rebuild on target if needed
cp "$ROOT/menubar/main.swift" "$PAYLOAD/menubar/" 2>/dev/null || true
cp "$ROOT/menubar/Info.plist" "$PAYLOAD/menubar/" 2>/dev/null || true
cp "$ROOT/menubar/build.sh" "$PAYLOAD/menubar/" 2>/dev/null || true

# Bundle official engine (no .git — smaller DMG; update-engine needs network later)
echo "Motor kopyalaniyor (git haric)..."
if command -v rsync >/dev/null 2>&1; then
	rsync -a \
		--exclude '.git' \
		--exclude '.github' \
		--exclude 'docs' \
		--exclude 'nfq/windows' \
		--exclude '*.o' \
		--exclude '*.d' \
		"$ROOT/upstream/" "$PAYLOAD/bundled/"
else
	cp -R "$ROOT/upstream" "$PAYLOAD/bundled"
	rm -rf "$PAYLOAD/bundled/.git" "$PAYLOAD/bundled/.github" 2>/dev/null || true
fi

# Ensure binary links
if [ -x "$PAYLOAD/bundled/binaries/my/tpws" ]; then
	mkdir -p "$PAYLOAD/bundled/tpws" "$PAYLOAD/bundled/ip2net" "$PAYLOAD/bundled/mdig"
	ln -sfn ../binaries/my/tpws "$PAYLOAD/bundled/tpws/tpws"
	ln -sfn ../binaries/my/ip2net "$PAYLOAD/bundled/ip2net/ip2net"
	ln -sfn ../binaries/my/mdig "$PAYLOAD/bundled/mdig/mdig"
fi

# --- Install payload script (called with root) ---
cat > "$PAYLOAD/install-as-root.sh" <<'ROOTEOF'
#!/bin/sh
# Privileged install entry — invoked by ZapretKurulum.app
set -e
PAYLOAD="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
export ZAPRET_HOME="$PAYLOAD"
export ZAPRET_UPSTREAM="$PAYLOAD/bundled"
export CONFIG_SRC="$PAYLOAD/config/config.macos-hostlist"
export HOSTLIST_SRC="$PAYLOAD/config/zapret-hosts-user.txt"

# Resolve console user for sudoers (installer may run as root without SUDO_USER)
if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
	CU=$(stat -f '%Su' /dev/console 2>/dev/null || true)
	if [ -n "$CU" ] && [ "$CU" != "root" ]; then
		export SUDO_USER="$CU"
	fi
fi

"$PAYLOAD/scripts/system-install.sh"

# Install menubar app (prebuilt — no swiftc required on target)
APP_SRC="$PAYLOAD/menubar/ZapretToggle.app"
if [ -d "$APP_SRC" ]; then
	rm -rf /Applications/ZapretToggle.app
	cp -R "$APP_SRC" /Applications/
	xattr -dr com.apple.quarantine /Applications/ZapretToggle.app 2>/dev/null || true
	echo "Menubar: /Applications/ZapretToggle.app"
else
	echo "UYARI: ZapretToggle.app payload icinde yok"
fi

# Optional: launch menubar for the console user
CU="${SUDO_USER:-$(stat -f '%Su' /dev/console 2>/dev/null)}"
if [ -n "$CU" ] && [ "$CU" != "root" ]; then
	sudo -u "$CU" open /Applications/ZapretToggle.app 2>/dev/null || true
fi

echo "INSTALL_OK"
ROOTEOF
chmod 755 "$PAYLOAD/install-as-root.sh"

# --- ZapretKurulum.app ---
# CRITICAL: embed payload INSIDE the .app bundle.
# macOS App Translocation (Gatekeeper) copies only the .app to a random path;
# sibling folders like ./payload on the DMG volume then disappear → "payload not found".
INSTALLER_APP="$STAGE/Zapret Kurulum.app"
CONTENTS="$INSTALLER_APP/Contents"
MACOS_D="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
mkdir -p "$MACOS_D" "$RES"

echo "payload uygulama icine gomuluyor (App Translocation guvenli)..."
rm -rf "$RES/payload"
cp -a "$PAYLOAD" "$RES/payload"
# Keep a copy on DMG root too (for Kurulum.command fallback + manual inspection)
# PAYLOAD already at $STAGE/payload

cat > "$MACOS_D/ZapretKurulum" <<'APPEOF'
#!/bin/sh
# Zapret Kurulum — double-click installer (Turkish UI via osascript)
set -e

# Resolve real path even under App Translocation / spaces / symlinks
SELF="$0"
case "$SELF" in
	/*) ;;
	*) SELF="$(pwd)/$SELF" ;;
esac
# Contents/MacOS/ZapretKurulum → app bundle root
APP_DIR="$(CDPATH= cd -- "$(dirname "$SELF")/../.." && pwd -P 2>/dev/null || CDPATH= cd -- "$(dirname "$SELF")/../.." && pwd)"
VOL_ROOT="$(CDPATH= cd -- "$APP_DIR/.." && pwd -P 2>/dev/null || CDPATH= cd -- "$APP_DIR/.." && pwd)"

# Search order: embedded (preferred) → sibling on volume → absolute volume roots
PAYLOAD=""
for CAND in \
	"$APP_DIR/Contents/Resources/payload" \
	"$VOL_ROOT/payload" \
	"/Volumes/Zapret Kurulum/payload" \
	"/Volumes/ZapretKurulum/payload"
do
	if [ -d "$CAND" ] && [ -x "$CAND/install-as-root.sh" ]; then
		PAYLOAD="$CAND"
		break
	fi
done

START=$(osascript <<'OSA'
try
	display dialog "Zapret macOS kurulumu

Bu program:
• Resmi bol-van/zapret motorunu kurar
• /opt/zapret altina yerlestirir
• Menu cubugu uygulamasini ekler
• Yonetici sifresi bir kez ister

VPN degildir. Cloudflare WARP kapali olmali.
Tailscale acik kalabilir.

Kuruluma baslansin mi?" buttons {"Iptal", "Kuruluma basla"} default button "Kuruluma basla" with title "Zapret Kurulum" with icon caution
	return "ok"
on error number -128
	return "cancel"
end try
OSA
)
[ "$START" = "ok" ] || exit 0

if [ -z "$PAYLOAD" ] || [ ! -d "$PAYLOAD" ]; then
	DETAIL=$(printf 'Aranan yerler:\n• %s\n• %s\n\nUygulama yolu:\n%s' \
		"$APP_DIR/Contents/Resources/payload" \
		"$VOL_ROOT/payload" \
		"$APP_DIR" | sed 's/"//g')
	osascript -e "display dialog \"HATA: payload klasoru bulunamadi.\n\n$DETAIL\n\nDMG'yi acik birakin; sadece .app'i kopyalamayin.\nAlternatif: Kurulum.command\" buttons {\"Tamam\"} default button 1 with title \"Zapret\" with icon stop"
	exit 1
fi

# Clear quarantine on payload scripts if needed
xattr -dr com.apple.quarantine "$PAYLOAD" 2>/dev/null || true
chmod -R u+rx "$PAYLOAD/scripts" "$PAYLOAD/install-as-root.sh" 2>/dev/null || true

LOG=$(mktemp /tmp/zapret-install.XXXXXX)
# Escape for AppleScript string (paths may contain spaces, e.g. /Volumes/Zapret Kurulum)
as_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
PAYLOAD_AS=$(as_escape "$PAYLOAD")
LOG_AS=$(as_escape "$LOG")
INSTALL_SH_AS=$(as_escape "$PAYLOAD/install-as-root.sh")

set +e
# Prefer osascript admin privileges (GUI password dialog)
osascript <<OSA 2>"$LOG.err"
do shell script "\"$INSTALL_SH_AS\" > \"$LOG_AS\" 2>&1" with administrator privileges
OSA
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
	# Fallback: open Terminal with sudo
	osascript <<OSA
try
	display dialog "Yonetici penceresi iptal edildi veya basarisiz.

Terminal ile kurulum denensin mi? (sifre sorulacak)" buttons {"Iptal", "Terminal ac"} default button "Terminal ac" with title "Zapret"
on error number -128
	return
end try
OSA
	osascript <<OSA
tell application "Terminal"
	activate
	do script "sudo \"$INSTALL_SH_AS\"; echo; echo 'Pencereyi kapatabilirsiniz.'; read -r _"
end tell
OSA
	exit 0
fi

if grep -q "INSTALL_OK" "$LOG" 2>/dev/null; then
	osascript <<'OSA'
display dialog "Kurulum tamamlandi!

Menü cubugunda Z ikonu gorunmeli.
• Z● = acik
• Z○ = kapali

Discord / engelli siteler icin menuden Ac.
WARP kapali olsun. Tailscale acik kalabilir.

DNS bozulursa: menüden «DNS duzelt (Wi‑Fi)»" buttons {"Tamam"} default button 1 with title "Zapret — Basarili" with icon note
OSA
else
	BODY=$(tail -c 600 "$LOG" 2>/dev/null | tr '\n' ' ' | sed 's/"//g')
	osascript -e "display dialog \"Kurulum tamamlanamadi.\n\n$BODY\" buttons {\"Tamam\"} default button 1 with title \"Zapret — Hata\" with icon stop"
	exit 1
fi

rm -f "$LOG" "$LOG.err" 2>/dev/null || true
exit 0
APPEOF
chmod 755 "$MACOS_D/ZapretKurulum"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>tr</string>
	<key>CFBundleExecutable</key>
	<string>ZapretKurulum</string>
	<key>CFBundleIdentifier</key>
	<string>local.zapret.kurulum</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Zapret Kurulum</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Also ship a double-click .command fallback
cat > "$STAGE/Kurulum.command" <<'CMDEOF'
#!/bin/sh
cd "$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PAYLOAD=""
for CAND in \
	"./payload" \
	"./Zapret Kurulum.app/Contents/Resources/payload" \
	"/Volumes/Zapret Kurulum/payload" \
	"/Volumes/Zapret Kurulum/Zapret Kurulum.app/Contents/Resources/payload"
do
	if [ -x "$CAND/install-as-root.sh" ]; then
		PAYLOAD="$CAND"
		break
	fi
done
if [ -z "$PAYLOAD" ]; then
	echo "payload bulunamadi. DMG acik mi? Dosyalari bozmayin."
	echo "Klasor: $(pwd)"
	ls -la
	read -r _
	exit 1
fi
echo "Zapret kurulumu — yonetici sifresi istenecek..."
echo "payload: $PAYLOAD"
sudo "$PAYLOAD/install-as-root.sh"
echo ""
echo "Bitti. Pencereyi kapatabilirsiniz."
read -r _
CMDEOF
chmod 755 "$STAGE/Kurulum.command"

# README Turkish
cat > "$STAGE/README-KURULUM.txt" <<'READMEEOF'
========================================
  Zapret macOS — Kurulum (arkadas icin)
========================================

Bu paket, resmi acik kaynak bol-van/zapret motorunu
Mac'inize kurar. VPN DEGILDIR; trafiğinizi sifrelemez.
Sadece bazi engelli sitelerin (Discord, YouTube, vb.)
erisimini kolaylastirmaya calisir.

----------------------------------------
3 ADIM
----------------------------------------

1) Bu DMG'yi acin (cift tik).

2) DMG penceresini ACIK birakin.
   "Zapret Kurulum" uygulamasina cift tiklayin
   (masaüstüne veya Applications'a TAŞIMAYIN —
    sadece .app kopyalanirsa kurulum bozulur).
   • macOS "kimligi dogrulanamadi" derse:
     sag tik > Ac > Ac
   • Mac sifrenizi bir kez girin (yonetici).

3) Menü cubugunda "Z" ikonu gorununce hazir.
   • Ac / Kapat menuden
   • Discord acilmazsa: "DNS duzelt (Wi‑Fi)"

Alternatif: Kurulum.command dosyasina cift tik
(Terminal acilir, sifre sorar).

----------------------------------------
ONEMLI
----------------------------------------

• Cloudflare WARP KAPALI olsun (cakisma).
• Tailscale ACIK kalabilir (sorun degil).
• Sadece resmi bol-van/zapret kaynak/binary.
• Kurulum yonetici (admin) sifresi ister — bir kez.
• Motor: /opt/zapret
• Kontrol: /usr/local/bin/zapret-ctl
• Menu: /Applications/ZapretToggle.app

----------------------------------------
KALDIRMA
----------------------------------------

Terminal:

  sudo /opt/zapret/local-tools/zapret-uninstall.sh --yes
  rm -rf /Applications/ZapretToggle.app

----------------------------------------
SORUN GIDERME
----------------------------------------

• Gatekeeper engeli: sag tik > Ac
• Sifre sormuyor / calismiyor: kurulumu tekrar calistirin
• Discord hâlâ yok: menüden DNS duzelt, WARP kapali mi bakin
• Acil kapat: menüden Kapat veya:
    sudo /usr/local/bin/zapret-ctl stop

Kaynak: https://github.com/bol-van/zapret
READMEEOF

# Optional: also put prebuilt ZapretToggle on DMG root for manual copy
cp -R "$ROOT/menubar/ZapretToggle.app" "$STAGE/ZapretToggle.app" 2>/dev/null || true

# Clear quarantine on stage
xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null || true

# --- Create DMG ---
echo "DMG olusturuluyor..."
rm -f "$DMG_PATH" "$DMG_VERSIONED"
hdiutil create \
	-volname "$VOL_NAME" \
	-srcfolder "$STAGE" \
	-ov \
	-format UDZO \
	-fs HFS+ \
	"$DMG_PATH"

cp -f "$DMG_PATH" "$DMG_VERSIONED"

# Size report
ls -lh "$DMG_PATH" "$DMG_VERSIONED"
file "$DMG_PATH"

echo ""
echo "=== Hazir ==="
echo "  $DMG_PATH"
echo "  $DMG_VERSIONED"
echo "  Mimari: $ARCH_NOTE (tpws + menubar)"
echo ""
echo "Gonderim: $DMG_PATH dosyasini arkadasina gonder."
echo "Alıcı: DMG ac > Zapret Kurulum cift tik > sifre gir."
