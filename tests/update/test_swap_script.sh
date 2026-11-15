#!/bin/zsh
# Runs leankeys/LeanKeysKit/Resources/swap-update.sh (the unattended update's app swap) against temp dirs,
# with `open` and `hdiutil` stubbed through PATH. Run: zsh tests/update/test_swap_script.sh

emulate -L zsh
setopt no_unset pipe_fail

root="${0:A:h:h:h}"
script="$root/leankeys/LeanKeysKit/Resources/swap-update.sh"
passed=0
failed=0
check() { # check <name> <command...>
  local name="$1"; shift
  if "$@"; then passed=$((passed + 1)); print -r -- "ok   $name"
  else failed=$((failed + 1)); print -r -- "FAIL $name"; fi
}

setup() { # setup [install folder name, default Applications]
  tmp="$(mktemp -d)"
  apps="$tmp/${1:-Applications}"
  mkdir -p "$tmp/bin" "$tmp/mount/LeanKeys.app/Contents" "$apps/LeanKeys.app/Contents"
  for tool in open hdiutil; do
    print -r -- "#!/bin/sh
echo $tool \"\$@\" >> \"$tmp/calls.log\"" > "$tmp/bin/$tool"
    chmod +x "$tmp/bin/$tool"
  done
  print new > "$tmp/mount/LeanKeys.app/Contents/marker"
  print old > "$apps/LeanKeys.app/Contents/marker"
  print dmg > "$tmp/update.dmg"
  : > "$tmp/calls.log"
  # A PID that has already exited, so the wait loop ends at once.
  /usr/bin/true & dead_pid=$!; wait $dead_pid 2>/dev/null
}

run_swap() {
  PATH="$tmp/bin:/usr/bin:/bin" /bin/bash "$script" \
    "$tmp/mount/LeanKeys.app" "$apps/LeanKeys.app" "$tmp/mount" "$tmp/update.dmg" "$dead_pid" \
    >/dev/null 2>&1
}

dest() { print -r -- "$apps/LeanKeys.app"; }

# 1. Successful swap.
setup
run_swap; code=$?
check "success: exit 0" [ $code -eq 0 ]
check "success: new app in place" [ "$(cat "$(dest)/Contents/marker")" = new ]
check "success: no .old left" [ ! -e "$(dest).old" ]
check "success: no .new left" [ ! -e "$(dest).new" ]
check "success: DMG deleted" [ ! -e "$tmp/update.dmg" ]
check "success: image detached" grep -qx "hdiutil detach $tmp/mount -quiet" "$tmp/calls.log"
check "success: relaunched" grep -qx "open $(dest)" "$tmp/calls.log"
rm -rf "$tmp"

# 2. Copy fails (unreadable file in the new app): the old app stays and is relaunched.
setup
print secret > "$tmp/mount/LeanKeys.app/Contents/unreadable"
chmod 000 "$tmp/mount/LeanKeys.app/Contents/unreadable"
run_swap; code=$?
check "copy failure: exit non-zero" [ $code -ne 0 ]
check "copy failure: old app kept" [ "$(cat "$(dest)/Contents/marker")" = old ]
check "copy failure: no .old left" [ ! -e "$(dest).old" ]
check "copy failure: no .new left" [ ! -e "$(dest).new" ]
check "copy failure: image detached" grep -qx "hdiutil detach $tmp/mount -quiet" "$tmp/calls.log"
check "copy failure: still relaunched" grep -qx "open $(dest)" "$tmp/calls.log"
chmod 600 "$tmp/mount/LeanKeys.app/Contents/unreadable"
rm -rf "$tmp"

# 3. Moving the new app into place fails: the old app is restored and relaunched.
setup
# A stub mv that fails only when moving .new into place.
print -r -- '#!/bin/sh
if [ "${1##*.}" = new ]; then exit 1; fi
exec /bin/mv "$@"' > "$tmp/bin/mv"
chmod +x "$tmp/bin/mv"
run_swap; code=$?
check "rename failure: exit non-zero" [ $code -ne 0 ]
check "rename failure: old app restored" [ "$(cat "$(dest)/Contents/marker")" = old ]
check "rename failure: no .old left" [ ! -e "$(dest).old" ]
check "rename failure: no .new left" [ ! -e "$(dest).new" ]
check "rename failure: still relaunched" grep -qx "open $(dest)" "$tmp/calls.log"
rm -rf "$tmp"

# 4. test_killed_mid_swap_restores_old: SIGTERM (logout, shutdown) right after the old app was moved aside.
#    The trap must put the old app back and relaunch it.
setup
# A stub mv that does the move-aside (DEST -> DEST.old), then kills the script that called it.
print -r -- '#!/bin/sh
/bin/mv "$@"
case "$2" in *.old) kill -TERM $PPID ;; esac' > "$tmp/bin/mv"
chmod +x "$tmp/bin/mv"
run_swap; code=$?
check "killed mid-swap: exit non-zero" [ $code -ne 0 ]
check "killed mid-swap: old app back in place" [ "$(cat "$(dest)/Contents/marker" 2>/dev/null)" = old ]
check "killed mid-swap: no .old left" [ ! -e "$(dest).old" ]
check "killed mid-swap: relaunched" grep -qx "open $(dest)" "$tmp/calls.log"
check "killed mid-swap: relaunched once" [ "$(grep -c '^open ' "$tmp/calls.log")" -eq 1 ]
rm -rf "$tmp"

# 5. test_leftover_old_new_from_crash: an earlier run died between the two moves, leaving only .old and a
#    half-copied .new. The leftover old app is recovered, then the update goes through.
setup
mv "$(dest)" "$(dest).old"
mkdir -p "$(dest).new/Contents"
print partial > "$(dest).new/Contents/marker"
run_swap; code=$?
check "crash leftovers: exit 0" [ $code -eq 0 ]
check "crash leftovers: new app in place" [ "$(cat "$(dest)/Contents/marker")" = new ]
check "crash leftovers: no .old left" [ ! -e "$(dest).old" ]
check "crash leftovers: no .new left" [ ! -e "$(dest).new" ]
check "crash leftovers: relaunched" grep -qx "open $(dest)" "$tmp/calls.log"
rm -rf "$tmp"

# 5b. Same leftovers, but the copy fails: the recovered old app must still come back.
setup
mv "$(dest)" "$(dest).old"
print secret > "$tmp/mount/LeanKeys.app/Contents/unreadable"
chmod 000 "$tmp/mount/LeanKeys.app/Contents/unreadable"
run_swap; code=$?
check "crash leftovers + copy failure: old app recovered" [ "$(cat "$(dest)/Contents/marker")" = old ]
check "crash leftovers + copy failure: relaunched" grep -qx "open $(dest)" "$tmp/calls.log"
chmod 600 "$tmp/mount/LeanKeys.app/Contents/unreadable"
rm -rf "$tmp"

# 6. A destination path with spaces.
setup "My Apps/Lean Keys"
run_swap; code=$?
check "spaces: exit 0" [ $code -eq 0 ]
check "spaces: new app in place" [ "$(cat "$(dest)/Contents/marker")" = new ]
check "spaces: no .old left" [ ! -e "$(dest).old" ]
check "spaces: relaunched with the full path" grep -qx "open $(dest)" "$tmp/calls.log"
rm -rf "$tmp"

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
