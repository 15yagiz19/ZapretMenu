#!/bin/sh
set -e
. "$(dirname "$0")/lib.sh"
require_root
log "Zapret baslatiliyor..."
# Pull latest workspace hostlist/config/custom.d into /opt before start
sync_workspace_to_opt
zapret_start
sleep 1
if is_running; then
	log "Zapret acik."
	exit 0
fi
log "UYARI: tpws baslamadi."
exit 1
