#!/bin/sh
# Safe engine update: backup -> git pull bol-van only -> make mac -> preserve config/hostlist -> restart -> self-test -> rollback on fail
set -e
. "$(dirname "$0")/lib.sh"
require_root

log_engine "=== Motor guncelleme basladi ==="

if [ ! -d "$ZAPRET_OPT" ]; then
	log_engine "HATA: /opt/zapret yok. Once system-install.sh calistirin."
	exit 1
fi

# Prefer /opt/zapret/src for system installs without a home workspace
if [ ! -d "$ZAPRET_UPSTREAM/.git" ] && [ -d /opt/zapret/src/.git ]; then
	ZAPRET_UPSTREAM="/opt/zapret/src"
fi
if [ ! -d "$ZAPRET_UPSTREAM/.git" ]; then
	# Fresh clone of official source only (portable / friend installs without bundled .git)
	log_engine "upstream git yok — resmi kaynak klonlaniyor: $ALLOWED_REMOTE"
	mkdir -p "$(dirname "$ZAPRET_UPSTREAM")"
	rm -rf "$ZAPRET_UPSTREAM"
	if ! git clone --depth 1 "$ALLOWED_REMOTE" "$ZAPRET_UPSTREAM" 2>&1 | tee -a "$ENGINE_UPDATE_LOG"; then
		log_engine "HATA: git clone basarisiz (ag / git gerekli)"
		exit 1
	fi
fi

# 1) Verify remote is official bol-van/zapret only
cd "$ZAPRET_UPSTREAM"
remote_url=$(git remote get-url origin 2>/dev/null || true)
case "$remote_url" in
	https://github.com/bol-van/zapret.git|https://github.com/bol-van/zapret|git@github.com:bol-van/zapret.git|git@github.com:bol-van/zapret)
		log_engine "Remote OK: $remote_url"
		;;
	*)
		log_engine "HATA: Remote hijack riski. origin=$remote_url beklenen=$ALLOWED_REMOTE"
		exit 2
		;;
esac

# 2) Timestamped backup of /opt/zapret + config copy in workspace
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/zapret.bak.$TS"
log_engine "Yedek: $BACKUP_DIR"
cp -a "$ZAPRET_OPT" "$BACKUP_DIR"
mkdir -p "$ZAPRET_HOME/backups"
cp -a "$ZAPRET_OPT/config" "$ZAPRET_HOME/backups/config.$TS" 2>/dev/null || true
if [ -f "$ZAPRET_OPT/ipset/zapret-hosts-user.txt" ]; then
	cp -a "$ZAPRET_OPT/ipset/zapret-hosts-user.txt" "$ZAPRET_HOME/backups/zapret-hosts-user.$TS.txt"
fi
# Keep a "latest" pointer for rollback
echo "$BACKUP_DIR" > /opt/zapret.latest-backup
log_engine "Son yedek isaretlendi: $BACKUP_DIR"

# Preserve user config + hostlist
CFG_SAVE="/tmp/zapret-cfg-save-$$"
HL_SAVE="/tmp/zapret-hl-save-$$"
cp -a "$ZAPRET_OPT/config" "$CFG_SAVE" 2>/dev/null || true
cp -a "$ZAPRET_OPT/ipset/zapret-hosts-user.txt" "$HL_SAVE" 2>/dev/null || true
# Also prefer workspace hostlist if newer source of truth
if [ -f "$HOSTLIST_SRC" ]; then
	cp -a "$HOSTLIST_SRC" "$HL_SAVE"
fi

rollback_from_backup() {
	log_engine "OTOMATIK ROLLBACK: $BACKUP_DIR"
	zapret_stop || true
	rm -rf "$ZAPRET_OPT"
	cp -a "$BACKUP_DIR" "$ZAPRET_OPT"
	# restore links if needed
	if [ -x "$ZAPRET_OPT/init.d/macos/zapret" ]; then
		ln -fs "$ZAPRET_OPT/init.d/macos/zapret.plist" /Library/LaunchDaemons/zapret.plist 2>/dev/null || true
		"$ZAPRET_OPT/init.d/macos/zapret" start || true
	fi
	log_engine "Rollback tamam."
}

# 3) git pull
log_engine "git pull..."
if ! git -C "$ZAPRET_UPSTREAM" pull --ff-only origin HEAD 2>&1 | tee -a "$ENGINE_UPDATE_LOG"; then
	# shallow clone may need unshallow or fetch
	log_engine "ff-only basarisiz, fetch + reset denenecek"
	git -C "$ZAPRET_UPSTREAM" fetch --depth 1 origin 2>&1 | tee -a "$ENGINE_UPDATE_LOG" || {
		log_engine "fetch basarisiz — yedek bozulmadi, cikis"
		exit 3
	}
	# stay on current branch tip after fetch if possible
	git -C "$ZAPRET_UPSTREAM" reset --hard FETCH_HEAD 2>&1 | tee -a "$ENGINE_UPDATE_LOG" || {
		log_engine "reset basarisiz"
		exit 3
	}
fi

# 4) make mac
log_engine "make mac..."
if ! (cd "$ZAPRET_UPSTREAM" && make mac) 2>&1 | tee -a "$ENGINE_UPDATE_LOG"; then
	log_engine "make mac BASARISIZ"
	exit 4
fi

# 5) Install binaries/scripts into /opt/zapret preserving config/hostlist
log_engine "Binary/script yerlestirme..."
zapret_stop || true

# Copy tree carefully: overwrite code, keep config/hostlist
# Use rsync-like selective copy
for d in common init.d ipset files binaries tpws nfq ip2net mdig docs; do
	if [ -e "$ZAPRET_UPSTREAM/$d" ]; then
		rm -rf "$ZAPRET_OPT/$d"
		cp -a "$ZAPRET_UPSTREAM/$d" "$ZAPRET_OPT/$d"
	fi
done
for f in install_easy.sh uninstall_easy.sh install_bin.sh install_prereq.sh blockcheck.sh config.default; do
	if [ -e "$ZAPRET_UPSTREAM/$f" ]; then
		cp -a "$ZAPRET_UPSTREAM/$f" "$ZAPRET_OPT/$f"
	fi
done

# Ensure binary symlinks under /opt/zapret
if [ -x "$ZAPRET_OPT/binaries/my/tpws" ]; then
	ln -sfn ../binaries/my/tpws "$ZAPRET_OPT/tpws/tpws"
	ln -sfn ../binaries/my/ip2net "$ZAPRET_OPT/ip2net/ip2net"
	ln -sfn ../binaries/my/mdig "$ZAPRET_OPT/mdig/mdig"
fi

# Fix perms
chmod 755 "$ZAPRET_OPT/init.d/macos/zapret" 2>/dev/null || true
find "$ZAPRET_OPT/binaries" -type f -exec chmod 755 {} \; 2>/dev/null || true
chown -R root:wheel "$ZAPRET_OPT" 2>/dev/null || true

# 6) Restore preserved config + hostlist
if [ -f "$CFG_SAVE" ]; then
	cp -a "$CFG_SAVE" "$ZAPRET_OPT/config"
	log_engine "Config korundu."
fi
mkdir -p "$ZAPRET_OPT/ipset"
if [ -f "$HL_SAVE" ]; then
	cp -a "$HL_SAVE" "$ZAPRET_OPT/ipset/zapret-hosts-user.txt"
	log_engine "Hostlist korundu."
fi
rm -f "$CFG_SAVE" "$HL_SAVE"

# Ensure GZIP_LISTS=0 and LISTS_RELOAD for macOS
if ! grep -q '^GZIP_LISTS=0' "$ZAPRET_OPT/config" 2>/dev/null; then
	echo 'GZIP_LISTS=0' >> "$ZAPRET_OPT/config"
fi

# 7) Restart
log_engine "Servis restart..."
ln -fs "$ZAPRET_OPT/init.d/macos/zapret.plist" /Library/LaunchDaemons/zapret.plist
if ! zapret_start; then
	log_engine "start basarisiz"
	rollback_from_backup
	exit 5
fi

# 8) Self-test
if self_test_engine; then
	log_engine "Self-test OK. Motor guncellendi."
	exit 0
fi

log_engine "Self-test BASARISIZ — rollback"
rollback_from_backup
if self_test_engine; then
	log_engine "Rollback sonrasi calisiyor."
	exit 6
fi
log_engine "Rollback sonrasi da basarisiz. Manuel kontrol gerekli."
exit 7
