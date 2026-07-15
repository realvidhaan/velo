#!/usr/bin/env bash
#
# Builds the FlowClone Swift package and assembles a runnable macOS .app bundle.
#
# Usage:
#   Scripts/build-app.sh [debug|release]
#
# Output: build/FlowClone.app
#
# The bundle is assembled and signed in a temp dir OUTSIDE any iCloud-synced
# folder, then copied into build/. This avoids a race where the iCloud
# fileprovider daemon re-stamps Finder/fileprovider xattrs onto the bundle
# between `xattr -c` and `codesign`, which makes codesign fail with
# "resource fork, Finder information, or similar detritus not allowed".
# Extended attributes added AFTER signing do not invalidate the signature.
#
# Signing: picks a stable identity so TCC Accessibility/Input Monitoring/
# Microphone grants survive rebuilds. Preference order:
#   1. an "Apple Development" identity (if you have an Apple Developer account)
#   2. the "FlowClone Local Dev" self-signed cert from Scripts/setup-signing.sh
#   3. ad-hoc (last resort — content-hashed, so grants RESET every build)
# Run `make setup` once to create #2 and avoid the ad-hoc fallback entirely.

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
BIN_NAME="FlowClone"
BUNDLE_ID="com.flowclone.app"
ENTITLEMENTS="$ROOT/Resources/FlowClone.entitlements"

echo "==> Building ($CONFIG)"
cd "$ROOT"
swift build -c "$CONFIG" --product FlowClone

BIN_PATH="$(swift build -c "$CONFIG" --product FlowClone --show-bin-path)/$BIN_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

# Stage in a non-synced temp dir.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/FlowClone.app"

echo "==> Assembling"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundle any SwiftPM resource bundles (e.g. *_*.bundle) next to the binary.
BIN_DIR="$(dirname "$BIN_PATH")"
for b in "$BIN_DIR"/*.bundle; do
    [[ -e "$b" ]] || continue
    cp -R "$b" "$APP/Contents/Resources/"
done

echo "==> Signing"
xattr -cr "$APP" 2>/dev/null || true

# Look up a stable signing identity, preferring a real Apple Development cert,
# then the local self-signed one, then nothing. `|| true` keeps `set -e`/pipefail
# from aborting when grep finds no match (the common case for each lookup).
find_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep "$1" | head -1 | awk -F'"' '{print $2}' || true
}
IDENTITY="$(find_identity "Apple Development")"
[[ -z "$IDENTITY" ]] && IDENTITY="$(find_identity "FlowClone Local Dev")"

if [[ -n "$IDENTITY" ]]; then
    echo "    using identity: $IDENTITY (stable — TCC grants persist)"
    codesign --force --options runtime \
        --identifier "$BUNDLE_ID" \
        --entitlements "$ENTITLEMENTS" \
        --sign "$IDENTITY" "$APP"
else
    echo "" >&2
    echo "!!  WARNING: no stable signing identity found — falling back to AD-HOC." >&2
    echo "!!  Ad-hoc signatures change every build, so macOS will RESET FlowClone's" >&2
    echo "!!  Accessibility / Input Monitoring / Microphone permissions on each" >&2
    echo "!!  rebuild. Run 'make setup' once to fix this permanently." >&2
    echo "" >&2
    codesign --force \
        --identifier "$BUNDLE_ID" \
        --entitlements "$ENTITLEMENTS" \
        --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "==> Installing to $BUILD_DIR/FlowClone.app"
mkdir -p "$BUILD_DIR"
rm -rf "$BUILD_DIR/FlowClone.app"
cp -R "$APP" "$BUILD_DIR/FlowClone.app"

echo "==> Done: $BUILD_DIR/FlowClone.app"
