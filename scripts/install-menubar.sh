#!/bin/sh
# Build and install ZapretToggle.app to /Applications
set -e

SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PKG_ROOT="$(CDPATH= cd -- "$SCRIPTS_DIR/.." && pwd)"
# Prefer menubar next to scripts (dev) or payload menubar
if [ -d "$PKG_ROOT/menubar" ]; then
	MENUBAR_DIR="$PKG_ROOT/menubar"
elif [ -d "$SCRIPTS_DIR/../menubar" ]; then
	MENUBAR_DIR="$(CDPATH= cd -- "$SCRIPTS_DIR/../menubar" && pwd)"
else
	echo "HATA: menubar klasoru bulunamadi"
	exit 1
fi

cd "$MENUBAR_DIR"
chmod +x build.sh
./build.sh

APP_SRC="$MENUBAR_DIR/ZapretToggle.app"
if [ ! -d "$APP_SRC" ]; then
	echo "Build basarisiz"
	exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
	rm -rf /Applications/ZapretToggle.app
	cp -R "$APP_SRC" /Applications/
	xattr -dr com.apple.quarantine /Applications/ZapretToggle.app 2>/dev/null || true
	echo "Kuruldu: /Applications/ZapretToggle.app"
else
	if cp -R "$APP_SRC" /Applications/ 2>/dev/null; then
		xattr -dr com.apple.quarantine /Applications/ZapretToggle.app 2>/dev/null || true
		echo "Kuruldu: /Applications/ZapretToggle.app"
	else
		echo "Applications yazilamadi. Su komutu calistirin:"
		echo "  sudo cp -R \"$APP_SRC\" /Applications/"
		echo "  open /Applications/ZapretToggle.app"
		open "$APP_SRC" 2>/dev/null || true
		exit 0
	fi
fi

echo "Aciliyor..."
open /Applications/ZapretToggle.app 2>/dev/null || open "$APP_SRC"

echo ""
echo "Login Item (giriste acilsin):"
echo "  Sistem Ayarlari > Genel > Login Items > + > ZapretToggle"
