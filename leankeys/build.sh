#!/bin/bash
# Builds LeanKeys.app from the Gõ Nhanh Xcode project and brands the built bundle; upstream files stay untouched.
#
# Usage: leankeys/build.sh [--version X.Y] [--dmg]
#   --version X.Y  CFBundleShortVersionString (default: "leankeys" in leankeys/LeanKeysKit/Resources/Versions.json)
#   --dmg          also write dist/LeanKeys-X.Y.dmg
# Output: dist/LeanKeys.app (universal: arm64 + x86_64). Exits non-zero if any step fails.
#
# Signing: ad-hoc by default. When LEANKEYS_SIGN_IDENTITY and LEANKEYS_NOTARY_PROFILE are both set, signs with that
# Developer ID identity (hardened runtime) and notarizes with that notarytool keychain profile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME=LeanKeys
BUNDLE_ID=io.github.anlvdt.leankeys
VERSION=""
MAKE_DMG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 && -n "$2" ]] || { echo "build.sh: --version needs a value" >&2; exit 2; }
            VERSION="$2"; shift 2 ;;
        --dmg) MAKE_DMG=true; shift ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "build.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["leankeys"])' \
        "$ROOT/leankeys/LeanKeysKit/Resources/Versions.json")"
fi

PB=/usr/libexec/PlistBuddy
DIST="$ROOT/dist"
APP="$DIST/$NAME.app"
DERIVED="$ROOT/build/dd"
ICON="$ROOT/leankeys/Branding/AppIcon.icns"
[[ -f "$ICON" ]] || { echo "build.sh: missing $ICON (run: swift leankeys/Branding/make-icon.swift)" >&2; exit 1; }

# 1. Rust core, universal. Reuses upstream's core.sh, which needs both rustup targets.
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
if command -v rustup >/dev/null 2>&1; then
    installed="$(rustup target list --installed)"
    for target in aarch64-apple-darwin x86_64-apple-darwin; do
        grep -qx "$target" <<<"$installed" || rustup target add "$target"
    done
fi
echo "==> Rust core"
bash "$ROOT/scripts/build/core.sh"

# 2. App. PRODUCT_NAME and PRODUCT_BUNDLE_IDENTIFIER are not passed to xcodebuild: command-line settings reach the
#    SwiftPM targets too, and PRODUCT_NAME=LeanKeys makes them collide ("Multiple commands produce LeanKeys.o").
#    The built bundle is renamed in step 4 instead.
echo "==> Xcode Release build ($VERSION)"
xcodebuild -project "$ROOT/platforms/macos/GoNhanh.xcodeproj" -scheme GoNhanh -configuration Release \
    -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGNING_ALLOWED=NO \
    build
BUILT="$DERIVED/Build/Products/Release/GoNhanh.app"
[[ -d "$BUILT" ]] || { echo "build.sh: xcodebuild produced no $BUILT" >&2; exit 1; }

# 3. Copy.
echo "==> dist/$NAME.app"
mkdir -p "$DIST"
rm -rf "$APP"
cp -R "$BUILT" "$APP"

# 4. Brand the bundle.
PLIST="$APP/Contents/Info.plist"
OLD_EXE="$($PB -c "Print :CFBundleExecutable" "$PLIST")"
if [[ "$OLD_EXE" != "$NAME" ]]; then
    mv "$APP/Contents/MacOS/$OLD_EXE" "$APP/Contents/MacOS/$NAME"
fi
$PB -c "Set :CFBundleExecutable $NAME" "$PLIST"
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
$PB -c "Set :CFBundleName $NAME" "$PLIST"
$PB -c "Set :CFBundleDisplayName $NAME" "$PLIST" 2>/dev/null || $PB -c "Add :CFBundleDisplayName string $NAME" "$PLIST"
$PB -c "Set :NSAppleEventsUsageDescription $NAME needs access to send keyboard events for Vietnamese input." "$PLIST" 2>/dev/null || true
# The asset catalog adds CFBundleIconName, which would make macOS use Gõ Nhanh's icon from Assets.car.
$PB -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
$PB -c "Set :CFBundleIconFile AppIcon" "$PLIST" 2>/dev/null || $PB -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# 5. Sign.
ENTITLEMENTS_PROD="$ROOT/platforms/macos/GoNhanh.entitlements.production"
if [[ -n "${LEANKEYS_SIGN_IDENTITY:-}" && -n "${LEANKEYS_NOTARY_PROFILE:-}" ]]; then
    echo "==> Signing with Developer ID: $LEANKEYS_SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS_PROD" -s "$LEANKEYS_SIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict "$APP"
    echo "==> Notarizing"
    ZIP="$ROOT/build/$NAME-notarize.zip"
    mkdir -p "$ROOT/build"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$LEANKEYS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
else
    # Ruling R28: the production entitlements, never the Debug ones (get-task-allow). No hardened runtime yet.
    echo "==> Signing ad-hoc"
    codesign --force --deep --entitlements "$ENTITLEMENTS_PROD" -s - "$APP"
    codesign --verify --deep --strict "$APP"
fi

# 6. DMG: the app plus an /Applications link. UpdateManager mounts it and copies $NAME.app.
if [[ "$MAKE_DMG" == true ]]; then
    DMG="$DIST/$NAME-$VERSION.dmg"
    echo "==> $DMG"
    STAGE="$ROOT/build/dmg"
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
    rm -rf "$STAGE"
    if [[ -n "${LEANKEYS_SIGN_IDENTITY:-}" && -n "${LEANKEYS_NOTARY_PROFILE:-}" ]]; then
        codesign --force --timestamp -s "$LEANKEYS_SIGN_IDENTITY" "$DMG"
        xcrun notarytool submit "$DMG" --keychain-profile "$LEANKEYS_NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi

echo "==> Done: $APP ($(lipo -archs "$APP/Contents/MacOS/$NAME"))"
