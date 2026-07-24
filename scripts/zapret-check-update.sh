#!/bin/sh
# Compare installed version with GitHub latest release (15yagiz19/ZapretMenu).
# stdout one of:
#   UP_TO_DATE <local>
#   UPDATE_AVAILABLE <local> <remote>
#   ERROR <message>
# Exit 0 always for menu parsing unless catastrophic.

set +e

REPO="15yagiz19/ZapretMenu"
API="https://api.github.com/repos/${REPO}/releases/latest"
SUPPORT="/Library/Application Support/Zapret"
LOCAL_FILE="$SUPPORT/version"
LOCAL="0.0.0"
if [ -f "$LOCAL_FILE" ]; then
	LOCAL=$(tr -d ' \t\r\nv' < "$LOCAL_FILE" | sed 's/^v//')
fi
[ -n "$LOCAL" ] || LOCAL="0.0.0"

# Allow offline/dev override
if [ -n "$ZAPRET_FORCE_REMOTE_VERSION" ]; then
	REMOTE=$(printf '%s' "$ZAPRET_FORCE_REMOTE_VERSION" | sed 's/^v//')
else
	JSON=$(curl -fsSL --max-time 20 \
		-H "Accept: application/vnd.github+json" \
		-H "User-Agent: ZapretMenu-check-update" \
		"$API" 2>/dev/null)
	if [ -z "$JSON" ]; then
		echo "ERROR network_or_api"
		exit 0
	fi
	REMOTE=$(printf '%s' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | sed 's/^v//')
fi

if [ -z "$REMOTE" ]; then
	echo "ERROR parse_tag"
	exit 0
fi

# Numeric-ish compare: split on .
ver_lt() {
	# returns 0 if $1 < $2
	a=$1; b=$2
	IFS=.
	set -- $a
	a1=${1:-0}; a2=${2:-0}; a3=${3:-0}
	set -- $b
	b1=${1:-0}; b2=${2:-0}; b3=${3:-0}
	unset IFS
	# strip non-digits
	a1=$(printf '%s' "$a1" | tr -cd '0-9'); a1=${a1:-0}
	a2=$(printf '%s' "$a2" | tr -cd '0-9'); a2=${a2:-0}
	a3=$(printf '%s' "$a3" | tr -cd '0-9'); a3=${a3:-0}
	b1=$(printf '%s' "$b1" | tr -cd '0-9'); b1=${b1:-0}
	b2=$(printf '%s' "$b2" | tr -cd '0-9'); b2=${b2:-0}
	b3=$(printf '%s' "$b3" | tr -cd '0-9'); b3=${b3:-0}
	if [ "$a1" -lt "$b1" ]; then return 0; fi
	if [ "$a1" -gt "$b1" ]; then return 1; fi
	if [ "$a2" -lt "$b2" ]; then return 0; fi
	if [ "$a2" -gt "$b2" ]; then return 1; fi
	if [ "$a3" -lt "$b3" ]; then return 0; fi
	return 1
}

if [ "$LOCAL" = "$REMOTE" ]; then
	echo "UP_TO_DATE $LOCAL"
	exit 0
fi
if ver_lt "$LOCAL" "$REMOTE"; then
	echo "UPDATE_AVAILABLE $LOCAL $REMOTE"
	exit 0
fi
# local newer or equal-ish
echo "UP_TO_DATE $LOCAL"
exit 0
