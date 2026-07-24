#!/bin/sh
# Download latest ZapretMenu release asset and clean-reinstall.
# Security: fixed repo, HTTPS, SHA256 required, install only known scripts.
set -e

. "$(dirname "$0")/lib.sh"
require_root

REPO="15yagiz19/ZapretMenu"
API="https://api.github.com/repos/${REPO}/releases/latest"
SUPPORT="/Library/Application Support/Zapret"
LOG="$SUPPORT/logs/self-update.log"
CACHE="$SUPPORT/cache"
ASSET_NAME="ZapretMenu-update.tar.gz"
SUMS_NAME="SHA256SUMS"

mkdir -p "$SUPPORT/logs" "$CACHE"
logu() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

logu "=== self-update basladi ==="

# 1) Check
CHECK_OUT=$("$(dirname "$0")/zapret-check-update.sh" 2>/dev/null || true)
logu "check: $CHECK_OUT"
case "$CHECK_OUT" in
	UP_TO_DATE*)
		logu "Zaten guncel."
		echo "$CHECK_OUT"
		exit 0
		;;
	UPDATE_AVAILABLE*)
		REMOTE=$(printf '%s' "$CHECK_OUT" | awk '{print $3}')
		LOCAL=$(printf '%s' "$CHECK_OUT" | awk '{print $2}')
		logu "Guncelleme: $LOCAL -> $REMOTE"
		;;
	*)
		# Force update if ZAPRET_FORCE_UPDATE=1 even when check fails
		if [ "${ZAPRET_FORCE_UPDATE:-0}" != "1" ]; then
			logu "HATA: guncelleme kontrolu basarisiz: $CHECK_OUT"
			echo "ERROR check_failed"
			exit 1
		fi
		REMOTE="latest"
		;;
esac

# 2) Fetch release JSON
JSON=$(curl -fsSL --max-time 60 \
	-H "Accept: application/vnd.github+json" \
	-H "User-Agent: ZapretMenu-self-update" \
	"$API")
TAG=$(printf '%s' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$TAG" ] || { logu "HATA: tag_name yok"; exit 1; }
REMOTE_VER=$(printf '%s' "$TAG" | sed 's/^v//')

# Extract browser_download_url for our assets (portable without jq)
extract_url() {
	name=$1
	printf '%s' "$JSON" | tr '{' '\n' | grep -F "\"name\": \"$name\"" | head -1 | \
		sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Fallback: scan all download URLs
if ! extract_url "$ASSET_NAME" | grep -q .; then
	ASSET_URL=$(printf '%s' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*ZapretMenu-update\.tar\.gz\)".*/\1/p' | head -1)
else
	ASSET_URL=$(extract_url "$ASSET_NAME")
fi
SUMS_URL=$(printf '%s' "$JSON" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*SHA256SUMS\)".*/\1/p' | head -1)

[ -n "$ASSET_URL" ] || { logu "HATA: $ASSET_NAME release asset yok"; echo "ERROR no_asset"; exit 1; }

allow_url() {
	case "$1" in
		https://github.com/*|https://objects.githubusercontent.com/*|https://release-assets.githubusercontent.com/*)
			return 0
			;;
		*)
			return 1
			;;
	esac
}
allow_url "$ASSET_URL" || { logu "HATA: asset host izinli degil: $ASSET_URL"; exit 1; }
if [ -n "$SUMS_URL" ]; then
	allow_url "$SUMS_URL" || { logu "HATA: sums host izinli degil"; exit 1; }
fi

WORKDIR=$(mktemp -d /tmp/zapretmenu-update.XXXXXX)
cleanup() { rm -rf "$WORKDIR" 2>/dev/null || true; }
trap cleanup EXIT

logu "Indiriliyor: $ASSET_URL"
curl -fsSL --max-time 300 -o "$WORKDIR/$ASSET_NAME" "$ASSET_URL"

if [ -n "$SUMS_URL" ]; then
	curl -fsSL --max-time 60 -o "$WORKDIR/$SUMS_NAME" "$SUMS_URL"
	EXPECTED=$(grep -E "[[:space:]]$ASSET_NAME\$|[[:space:]]\./$ASSET_NAME\$" "$WORKDIR/$SUMS_NAME" | awk '{print $1}' | head -1)
	if [ -z "$EXPECTED" ]; then
		EXPECTED=$(grep -F "$ASSET_NAME" "$WORKDIR/$SUMS_NAME" | awk '{print $1}' | head -1)
	fi
	[ -n "$EXPECTED" ] || { logu "HATA: SHA256SUMS icinde $ASSET_NAME yok"; echo "ERROR no_checksum"; exit 1; }
	ACTUAL=$(shasum -a 256 "$WORKDIR/$ASSET_NAME" | awk '{print $1}')
	if [ "$EXPECTED" != "$ACTUAL" ]; then
		logu "HATA: SHA256 uyusmuyor expected=$EXPECTED actual=$ACTUAL"
		echo "ERROR checksum_mismatch"
		exit 1
	fi
	logu "SHA256 OK: $ACTUAL"
else
	logu "HATA: SHA256SUMS asset zorunlu — red"
	echo "ERROR no_sums_asset"
	exit 1
fi

# 3) Extract
tar -xzf "$WORKDIR/$ASSET_NAME" -C "$WORKDIR"
PAYLOAD=""
if [ -d "$WORKDIR/payload" ]; then
	PAYLOAD="$WORKDIR/payload"
elif [ -f "$WORKDIR/install-as-root.sh" ]; then
	PAYLOAD="$WORKDIR"
else
	# single top-level dir
	for d in "$WORKDIR"/*; do
		if [ -d "$d" ] && [ -f "$d/install-as-root.sh" -o -d "$d/scripts" ]; then
			PAYLOAD="$d"
			break
		fi
	done
fi
[ -n "$PAYLOAD" ] && [ -d "$PAYLOAD" ] || { logu "HATA: payload acilamadi"; exit 1; }

# Prefer install-as-root if present
INSTALL_SH=""
if [ -x "$PAYLOAD/install-as-root.sh" ]; then
	INSTALL_SH="$PAYLOAD/install-as-root.sh"
elif [ -x "$PAYLOAD/scripts/system-install.sh" ]; then
	INSTALL_SH="$PAYLOAD/scripts/system-install.sh"
else
	logu "HATA: install script yok"
	exit 1
fi

logu "Kurulum: $INSTALL_SH (clean reinstall, surum=$REMOTE_VER)"
export ZAPRET_CLEAN_REINSTALL=1
export ZAPRET_VERSION="$REMOTE_VER"
export ZAPRET_FIX_DNS=0
export ZAPRET_HOME="$PAYLOAD"
if [ -d "$PAYLOAD/bundled" ]; then
	export ZAPRET_UPSTREAM="$PAYLOAD/bundled"
fi
if [ -f "$PAYLOAD/config/config.macos-hostlist" ]; then
	export CONFIG_SRC="$PAYLOAD/config/config.macos-hostlist"
fi
if [ -f "$PAYLOAD/config/zapret-hosts-user.txt" ]; then
	export HOSTLIST_SRC="$PAYLOAD/config/zapret-hosts-user.txt"
fi

set +e
if [ "$(basename "$INSTALL_SH")" = "install-as-root.sh" ]; then
	"$INSTALL_SH" >> "$LOG" 2>&1
else
	"$INSTALL_SH" >> "$LOG" 2>&1
fi
RC=$?
set -e

# Menubar from payload
if [ -d "$PAYLOAD/menubar/ZapretToggle.app" ]; then
	rm -rf /Applications/ZapretToggle.app
	cp -R "$PAYLOAD/menubar/ZapretToggle.app" /Applications/
	xattr -dr com.apple.quarantine /Applications/ZapretToggle.app 2>/dev/null || true
	logu "Menubar guncellendi"
fi

# Ensure version file
printf '%s\n' "$REMOTE_VER" > "$SUPPORT/version"
chmod 644 "$SUPPORT/version"

if [ "$RC" -ne 0 ]; then
	logu "HATA: kurulum exit=$RC"
	echo "ERROR install_failed"
	exit 1
fi

# Self-test
sleep 2
if pgrep -xq tpws 2>/dev/null; then
	logu "OK: self-update tamam surum=$REMOTE_VER tpws calisiyor"
else
	logu "UYARI: tpws yok — start deneniyor"
	if [ -x /usr/local/bin/zapret-ctl ]; then
		/usr/local/bin/zapret-ctl start >> "$LOG" 2>&1 || true
	fi
fi

echo "UPDATED $REMOTE_VER"
logu "=== self-update bitti ==="
exit 0
