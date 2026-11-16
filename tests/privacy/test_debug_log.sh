#!/bin/zsh
# The macOS app must never log to the shared /tmp/gonhanh_debug.log, nor write typed text or character key codes
# into its debug log (spec §18.2). Guards against an upstream Gõ Nhanh sync bringing either back.
# Run: zsh tests/privacy/test_debug_log.sh

emulate -L zsh
setopt pipe_fail
root="${0:A:h:h:h}"
failed=0
fail() { failed=1; print -r -- "FAIL $1"; }

if grep -rn 'gonhanh_debug\.log' "$root/platforms/macos" --include='*.swift'; then
  fail "a /tmp/gonhanh_debug.log path is back in platforms/macos"
fi
# Typed text quoted into a log line: chars='…', char='…', text='…'.
if grep -nE "Log\.[a-z]+\(.*(chars|char|text)='\\\\\(" "$root/platforms/macos/RustBridge.swift"; then
  fail "a log line writes typed text"
fi
# Raw key codes: Log.key must label codes through DebugLog.keyLabel, and keyDown lines too.
if grep -nE 'write\("K:\\\(code\)' "$root/platforms/macos/RustBridge.swift"; then
  fail "Log.key writes raw key codes"
fi
if grep -nE 'Log\.[a-z]+\("keyDown: code=\\\(keyCode\)' "$root/platforms/macos/RustBridge.swift"; then
  fail "keyDown logs raw key codes"
fi
grep -q 'logPath = DebugLog.path' "$root/platforms/macos/RustBridge.swift" || fail "Log does not use DebugLog.path"

(( failed )) && exit 1
print -r -- "ok   debug log: private path, no typed text, no character key codes"
