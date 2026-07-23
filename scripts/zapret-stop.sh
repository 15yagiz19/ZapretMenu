#!/bin/sh
set -e
. "$(dirname "$0")/lib.sh"
require_root
log "Zapret durduruluyor..."
zapret_stop
log "Zapret kapali."
exit 0
