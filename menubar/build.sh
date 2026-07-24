#!/bin/sh
# Build ZapretToggle.app (Swift + AppKit, universal if possible)
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ZapretToggle"
APP_DIR="$DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
# Prefer an SDK that matches the installed swiftc (avoid 27.x SDK with older CLT)
if [ -n "$SDKROOT" ] && [ -d "$SDKROOT" ]; then
	SDK="$SDKROOT"
elif [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]; then
	SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
elif [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
	SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
	SDK="$(xcrun --show-sdk-path)"
fi
MIN_OS="${MIN_OS:-13.0}"

echo "Derleniyor: $APP_NAME (universal arm64+x86_64)..."
echo "SDK: $SDK"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"

ARM_OUT=$(mktemp)
X86_OUT=$(mktemp)
trap 'rm -f "$ARM_OUT" "$X86_OUT"' EXIT

swiftc -O \
	-target "arm64-apple-macos${MIN_OS}" \
	-sdk "$SDK" \
	-framework AppKit \
	-framework Foundation \
	-o "$ARM_OUT" \
	"$DIR/main.swift"

if swiftc -O \
	-target "x86_64-apple-macos${MIN_OS}" \
	-sdk "$SDK" \
	-framework AppKit \
	-framework Foundation \
	-o "$X86_OUT" \
	"$DIR/main.swift" 2>/dev/null; then
	lipo -create -output "$MACOS/$APP_NAME" "$ARM_OUT" "$X86_OUT"
	echo "Universal binary: arm64 + x86_64"
else
	cp "$ARM_OUT" "$MACOS/$APP_NAME"
	echo "UYARI: yalnizca arm64 derlendi (x86_64 basarisiz)"
fi

cp "$DIR/Info.plist" "$CONTENTS/Info.plist"
echo -n "APPL????" > "$CONTENTS/PkgInfo"
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

echo "OK: $APP_DIR"
file "$MACOS/$APP_NAME"
echo "Calistir: open \"$APP_DIR\""
echo "Kurulum:  cp -R \"$APP_DIR\" /Applications/"
