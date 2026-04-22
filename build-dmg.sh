#!/usr/bin/env bash
# Build, sign, notarize, and package VibeType as a .dmg installer.
#
# Prereqs (one-time):
#   1. Developer ID Application certificate imported into your login keychain.
#      Check: security find-identity -p codesigning -v | grep "Developer ID Application"
#   2. notarytool keychain profile stored once with:
#        xcrun notarytool store-credentials vibetype-notary \
#            --apple-id you@example.com \
#            --team-id  XXXXXXXXXX \
#            --password app-specific-password
#
# Usage:
#   ./build-dmg.sh                 # full flow: build + sign + notarize + staple
#   VERSION=1.2.3 ./build-dmg.sh   # override version (default 0.1.0)
#   SKIP_NOTARIZE=1 ./build-dmg.sh # dev build: sign but skip notarize/staple
#
# Override knobs (env vars):
#   VERSION           bundle version           default: 0.1.0
#   BUNDLE_ID         CFBundleIdentifier       default: com.vibetype.app
#   SIGNING_IDENTITY  codesign identity        default: auto-discovered
#   NOTARY_PROFILE    notarytool profile name  default: vibetype-notary
#   SKIP_NOTARIZE     1 to skip notarization   default: unset

set -euo pipefail

APP_NAME="VibeType"
VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.vibetype.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-vibetype-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

BUILD_DIR="build"
DIST_DIR="dist"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
ENTITLEMENTS="${BUILD_DIR}/${APP_NAME}.entitlements"
STAGING="${BUILD_DIR}/dmg-staging"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

log() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
err() { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; }

# ---- discover signing identity ----
if [ -z "${SIGNING_IDENTITY:-}" ]; then
    SIGNING_IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi
if [ -z "${SIGNING_IDENTITY:-}" ]; then
    err "no 'Developer ID Application' identity found in the login keychain."
    err "Install your cert, or export SIGNING_IDENTITY='Developer ID Application: ... (TEAMID)'"
    exit 1
fi
log "signing identity: ${SIGNING_IDENTITY}"

# ---- verify notarytool profile up front (fail fast before a long build) ----
if [ "$SKIP_NOTARIZE" != "1" ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        err "notarytool keychain profile '${NOTARY_PROFILE}' not found."
        err "Run once:"
        err "  xcrun notarytool store-credentials ${NOTARY_PROFILE} \\"
        err "      --apple-id you@example.com --team-id XXXXXXXXXX --password app-pwd"
        err "Or skip notarization with: SKIP_NOTARIZE=1 $0"
        exit 1
    fi
    log "notarytool profile: ${NOTARY_PROFILE}"
fi

# ---- clean + build release ----
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

log "building release binary..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [ ! -f "$BIN_PATH" ]; then
    err "expected binary at ${BIN_PATH} but it's missing"
    exit 1
fi

# ---- assemble .app bundle ----
log "assembling ${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"
cp "$BIN_PATH" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
chmod 755 "${APP_PATH}/Contents/MacOS/${APP_NAME}"

# ---- generate app icon from logo.png (if present) ----
LOGO_PNG="logo.png"
ICON_PLIST_ENTRY=""
if [ -f "$LOGO_PNG" ]; then
    log "generating AppIcon.icns from ${LOGO_PNG}"
    ICONSET="${BUILD_DIR}/${APP_NAME}.iconset"
    mkdir -p "$ICONSET"
    sips -z 16   16   "$LOGO_PNG" --out "$ICONSET/icon_16x16.png"       >/dev/null
    sips -z 32   32   "$LOGO_PNG" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
    sips -z 32   32   "$LOGO_PNG" --out "$ICONSET/icon_32x32.png"       >/dev/null
    sips -z 64   64   "$LOGO_PNG" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
    sips -z 128  128  "$LOGO_PNG" --out "$ICONSET/icon_128x128.png"     >/dev/null
    sips -z 256  256  "$LOGO_PNG" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
    sips -z 256  256  "$LOGO_PNG" --out "$ICONSET/icon_256x256.png"     >/dev/null
    sips -z 512  512  "$LOGO_PNG" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
    sips -z 512  512  "$LOGO_PNG" --out "$ICONSET/icon_512x512.png"     >/dev/null
    sips -z 1024 1024 "$LOGO_PNG" --out "$ICONSET/icon_512x512@2x.png"  >/dev/null
    iconutil -c icns "$ICONSET" -o "${APP_PATH}/Contents/Resources/AppIcon.icns"
    ICON_PLIST_ENTRY='    <key>CFBundleIconFile</key>         <string>AppIcon</string>'
else
    log "logo.png not found in project root; packaging without an app icon"
fi

cat > "${APP_PATH}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>          <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>                <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>         <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundleVersion</key>             <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
    <key>LSUIElement</key>                 <false/>
${ICON_PLIST_ENTRY}
</dict>
</plist>
EOF

# Minimal entitlements — hardened runtime defaults, no special capabilities.
# The global key monitor needs Accessibility at runtime (user-granted via TCC),
# which does not require an entitlement.
cat > "$ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

# ---- sign app ----
log "signing app with hardened runtime"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

# ---- build DMG (staging so we can add an /Applications drop target) ----
log "creating DMG"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

log "signing DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

# ---- notarize ----
if [ "$SKIP_NOTARIZE" = "1" ]; then
    log "SKIP_NOTARIZE=1 — leaving DMG un-notarized (dev build)"
else
    log "submitting to Apple notary service (blocking until verdict)"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    log "stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

log "done: ${DMG_PATH}"
