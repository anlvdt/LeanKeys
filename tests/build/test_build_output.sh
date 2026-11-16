#!/bin/zsh
# Builds LeanKeys with leankeys/build.sh and checks the bundle it writes.
# Run: zsh tests/build/test_build_output.sh   (slow: Rust core + Xcode Release)
# Set LEANKEYS_SKIP_BUILD=1 to check an existing dist/LeanKeys.app without rebuilding.

emulate -L zsh
setopt no_unset pipe_fail

root="${0:A:h:h:h}"
app="$root/dist/LeanKeys.app"
plist="$app/Contents/Info.plist"
pb=/usr/libexec/PlistBuddy
# The current release number, so the build left in dist/ is the one the next release ships (not a stale 1.0).
version="$(sed -n 's/.*"leankeys" *: *"\([^"]*\)".*/\1/p' "$root/leankeys/LeanKeysKit/Resources/Versions.json")"
[[ -n "$version" ]] || { print -r -- "FAIL no leankeys version in Versions.json"; exit 1; }

passed=0
failed=0
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    passed=$((passed + 1)); print -r -- "ok   $1"
  else
    failed=$((failed + 1)); print -r -- "FAIL $1: expected '$2', got '$3'"
  fi
}
key() { $pb -c "Print :$1" "$plist" 2>/dev/null || print -r -- "<missing>"; }

if [[ -z "${LEANKEYS_SKIP_BUILD:-}" ]]; then
  if ! "$root/leankeys/build.sh" --version "$version"; then
    print -r -- "FAIL leankeys/build.sh exited non-zero"
    exit 1
  fi
fi

if [[ ! -f "$plist" ]]; then
  print -r -- "FAIL no $plist"
  exit 1
fi

check CFBundleIdentifier io.github.anlvdt.leankeys "$(key CFBundleIdentifier)"
check CFBundleName LeanKeys "$(key CFBundleName)"
check CFBundleDisplayName LeanKeys "$(key CFBundleDisplayName)"
check CFBundleShortVersionString "$version" "$(key CFBundleShortVersionString)"
check CFBundleIconFile AppIcon "$(key CFBundleIconFile)"
check NSHumanReadableCopyright "© 2025 Kha Phan (Gõ Nhanh) · © 2026 LeanKeys · GPL-3.0" "$(key NSHumanReadableCopyright)"
check "CFBundleIconName absent" "<missing>" "$(key CFBundleIconName)"
exe="$(key CFBundleExecutable)"
check "executable present" yes "$([[ -x "$app/Contents/MacOS/$exe" ]] && print yes || print no)"
check "icon is LeanKeys'" yes "$(cmp -s "$app/Contents/Resources/AppIcon.icns" "$root/leankeys/Branding/AppIcon.icns" && print yes || print no)"
archs="$(lipo -archs "$app/Contents/MacOS/$exe" 2>/dev/null)"
check "universal binary" yes "$([[ "$archs" == *arm64* && "$archs" == *x86_64* ]] && print yes || print no)"
codesign --verify --deep --strict "$app" 2>/dev/null
check "codesign --verify --deep" 0 "$?"
# Ruling R28: a shipped build must not carry the Debug entitlement get-task-allow.
ents="$(codesign -d --entitlements - "$app" 2>&1)"
check "entitlements readable" yes "$([[ "$ents" == *com.apple.security.app-sandbox* ]] && print yes || print no)"
check "no get-task-allow" no "$([[ "$ents" == *get-task-allow* ]] && print yes || print no)"
# Security audit HIGH-1: hardened runtime on, and no entitlement that lets other code into the process (dyld
# injection, unsigned pages) or that nothing uses (Apple Events).
info="$(codesign -dv "$app" 2>&1)"
check "hardened runtime" yes "$([[ "$info" == *flags=0x*'('*runtime*')'* ]] && print yes || print no)"
for ent in cs.disable-library-validation cs.allow-jit cs.allow-unsigned-executable-memory \
  cs.disable-executable-page-protection automation.apple-events; do
  check "no $ent" no "$([[ "$ents" == *com.apple.security.$ent* ]] && print yes || print no)"
done
check "no NSAppleEventsUsageDescription" "<missing>" "$(key NSAppleEventsUsageDescription)"
# A self-signed build keeps its certificate-leaf designated requirement, so users keep their Accessibility grant.
if [[ "$info" == *"Authority=LeanKeys Self-Signed"* ]]; then
  check "designated requirement is the certificate leaf" yes \
    "$([[ "$(codesign -d -r- "$app" 2>&1)" == *'certificate leaf'* ]] && print yes || print no)"
fi

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
