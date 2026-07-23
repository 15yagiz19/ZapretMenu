#!/bin/sh
set -e
. "$(dirname "$0")/lib.sh"
require_root

log "Hostlist/config guncelleniyor..."

# Prefer workspace source of truth, then /opt
if [ -f "$HOSTLIST_SRC" ] || [ -f "$CONFIG_SRC" ]; then
	sync_workspace_to_opt
	log "Workspace hostlist/config/custom.d -> /opt/zapret"
fi

if [ -x "$ZAPRET_OPT/ipset/get_user.sh" ]; then
	# shellcheck disable=SC1091
	. "$ZAPRET_OPT/config" 2>/dev/null || true
	export GZIP_LISTS=0
	"$ZAPRET_OPT/ipset/get_user.sh" || log "get_user.sh uyari (devam)"
fi

# Signal tpws to reload hostlists if running
if is_running; then
	pkill -HUP -x tpws 2>/dev/null || true
	if [ -x "$ZAPRET_INIT" ]; then
		"$ZAPRET_INIT" reload-fw-tables 2>/dev/null || true
	fi
fi

log "Listeler guncellendi."
exit 0
