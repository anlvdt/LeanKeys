#!/bin/bash
# Builds LeanKeys.app from the Gõ Nhanh Xcode project and brands the built bundle; upstream files stay untouched.
#
# Usage: leankeys/build.sh [--version X.Y] [--dmg]
#   --version X.Y  CFBundleShortVersionString (default: "leankeys" in leankeys/LeanKeysKit/Resources/Versions.json)
#   --dmg          also write dist/LeanKeys-X.Y.dmg
# Output: dist/LeanKeys.app (universal: arm64 + x86_64). Exits non-zero if any step fails.
#
# Signing: when LEANKEYS_SIGN_IDENTITY and LEANKEYS_NOTARY_PROFILE are both set, signs with that Developer ID identity
# and notarizes with that notarytool keychain profile. Otherwise signs with the "LeanKeys Self-Signed" identity when it
# is in the keychain (see sync/make-signing-cert.sh), and ad-hoc when it is not. Every kind uses the hardened runtime
# and leankeys/LeanKeys.entitlements (security audit HIGH-1); the build fails if the signed app lacks the runtime flag.
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
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "build.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Prints the signing kind for step 5: developer-id, self-signed or adhoc.
# $1 is the output of `security find-identity -p codesigning` (no -v, so untrusted identities count too).
pick_signing_kind() {
    local identities="$1"
    if [[ -n "${LEANKEYS_SIGN_IDENTITY:-}" && -n "${LEANKEYS_NOTARY_PROFILE:-}" ]]; then
        echo developer-id
    elif [[ "$identities" == *'"LeanKeys Self-Signed"'* ]]; then
        echo self-signed
    else
        echo adhoc
    fi
}
# Fails (non-zero, message on stderr) when LEANKEYS_REQUIRE_STABLE_SIGNING=1 and the kind is ad-hoc. sync/sync.sh sets it:
# an ad-hoc build would cost every user their Accessibility grant, so the job must fail instead of shipping it.
# $1 is the kind from pick_signing_kind.
require_stable_signing() {
    local kind="$1"
    if [[ "${LEANKEYS_REQUIRE_STABLE_SIGNING:-0}" == 1 && "$kind" != developer-id && "$kind" != self-signed ]]; then
        echo 'Stable signing required (LEANKEYS_REQUIRE_STABLE_SIGNING=1) but "LeanKeys Self-Signed" was not found — unlock the login keychain or run sync/make-signing-cert.sh' >&2
        return 1
    fi
}
[[ "${LEANKEYS_SOURCE_ONLY:-}" == 1 ]] && return 0

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

# Signing kind is picked before the expensive build so a required-but-missing stable identity fails fast.
# LeanKeys' own entitlements, not upstream's GoNhanh.entitlements.production: sandbox off and nothing else (HIGH-1).
ENTITLEMENTS_PROD="$ROOT/leankeys/LeanKeys.entitlements"
SIGN_KIND="$(pick_signing_kind "$(security find-identity -p codesigning 2>/dev/null || true)")"
require_stable_signing "$SIGN_KIND" || exit 1
if [[ -n "${LEANKEYS_SIGN_IDENTITY:-}" && -z "${LEANKEYS_NOTARY_PROFILE:-}" ]]; then
    echo "build.sh: warning: LEANKEYS_SIGN_IDENTITY is set without LEANKEYS_NOTARY_PROFILE; not notarizing, and the Developer ID path needs both" >&2
fi

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
# Nothing sends Apple Events (HIGH-1): no usage string for them.
$PB -c "Delete :NSAppleEventsUsageDescription" "$PLIST" 2>/dev/null || true
# Finder's Get Info: Gõ Nhanh's "All rights reserved." line does not fit a GPL derivative.
$PB -c "Set :NSHumanReadableCopyright © 2025 Kha Phan (Gõ Nhanh) · © 2026 $NAME · GPL-3.0" "$PLIST" 2>/dev/null ||
    $PB -c "Add :NSHumanReadableCopyright string © 2025 Kha Phan (Gõ Nhanh) · © 2026 $NAME · GPL-3.0" "$PLIST"
# The asset catalog adds CFBundleIconName, which would make macOS use Gõ Nhanh's icon from Assets.car.
$PB -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
$PB -c "Set :CFBundleIconFile AppIcon" "$PLIST" 2>/dev/null || $PB -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# 5. Sign.
if [[ "$SIGN_KIND" == developer-id ]]; then
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
elif [[ "$SIGN_KIND" == self-signed ]]; then
    # Stable identity: macOS keeps the Accessibility grant across updates because the designated requirement stays the same.
    # Never falls back to ad-hoc: an ad-hoc build would cost every user their grant.
    echo "==> Signing self-signed"
    if ! codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PROD" -s "LeanKeys Self-Signed" "$APP"; then
        echo "Signing with LeanKeys Self-Signed failed — unlock the login keychain or run sync/make-signing-cert.sh" >&2
        exit 1
    fi
    codesign --verify --deep --strict "$APP"
    reqs="$(codesign -dr - "$APP" 2>&1 || true)"
    if [[ "$reqs" != *"certificate leaf"* ]]; then
        echo "Signing with LeanKeys Self-Signed failed — unlock the login keychain or run sync/make-signing-cert.sh" >&2
        exit 1
    fi
else
    # Ruling R28: the production entitlements, never the Debug ones (get-task-allow).
    echo "==> Signing ad-hoc"
    codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PROD" -s - "$APP"
    codesign --verify --deep --strict "$APP"
fi
# HIGH-1: without the hardened runtime, any process of the user could relaunch LeanKeys with DYLD_INSERT_LIBRARIES and
# inherit its Accessibility grant. "flags=0x10000(runtime)", or "flags=0x10002(adhoc,runtime)" for ad-hoc.
# Captured first: under pipefail, grep -q closing the pipe early would fail codesign with SIGPIPE.
sig_info="$(codesign -dv "$APP" 2>&1 || true)"
if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime[^)]*\)' <<<"$sig_info"; then
    echo "build.sh: $APP is not signed with the hardened runtime" >&2
    exit 1
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
