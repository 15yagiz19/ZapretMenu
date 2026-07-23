#!/bin/sh
. "$(dirname "$0")/lib.sh"
# status is readable without root for process checks
zapret_status
exit $?
