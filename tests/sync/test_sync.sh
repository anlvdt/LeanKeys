#!/bin/zsh
# Tests for sync/sync.sh. Each case builds, under mktemp -d, a fake Gõ Nhanh
# upstream repo, a fake Vikey repo, and a fork of the upstream ("fork") with
# vendor/vikey as a submodule and the LeanKeys sync files, then runs
# sync.sh --repo <fork> --no-notify against it.
#
# Run: zsh tests/sync/test_sync.sh

emulate -L zsh
setopt no_unset pipe_fail

src="${0:A:h:h:h}"
sync_sh="$src/sync/sync.sh"

# Keep the user's git config (signing, hooks, templates) out of the test repos;
# allow file:// submodules, which git refuses by default. sync.sh inherits this.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export LEANKEYS_MAIN_BRANCH=main

base="$(mktemp -d)"
sleeper=""
cleanup() {
  [[ -n "$sleeper" ]] && kill "$sleeper" 2>/dev/null
  rm -rf "$base"
}
trap cleanup EXIT

passed=0
failed=0
out=""
rc=0
today="$(date +%F)"

# Sets $up, $vk, $fork for case $1. Upstream: H (with a hooked line) and A,
# tag v1.0.165. Vikey: App/Core/VikeyCore.mm, tag v1.0.33. Fork: clone of
# upstream on branch main with the hook applied, sync files, and the submodule.
setup() {
  local d="$base/$1"
  up="$d/upstream" vk="$d/vikey" fork="$d/fork"
  mkdir -p "$up" "$vk"

  git -C "$up" init -q -b main
  printf 'line 1\nhook here\nline 3\n' > "$up/H"
  printf 'alpha\n' > "$up/A"
  git -C "$up" add -A && git -C "$up" commit -q -m 'upstream base'
  git -C "$up" tag v1.0.165

  git -C "$vk" init -q -b main
  mkdir -p "$vk/App/Core"
  printf 'core v1\n' > "$vk/App/Core/VikeyCore.mm"
  git -C "$vk" add -A && git -C "$vk" commit -q -m 'vikey base'
  git -C "$vk" tag v1.0.33

  git clone -q "$up" "$fork" 2>/dev/null
  git -C "$fork" checkout -q -B main v1.0.165
  git -C "$fork" remote rename origin upstream
  printf 'line 1\nhook here // LEANKEYS-HOOK: myhook\nline 3\n' > "$fork/H"
  mkdir -p "$fork/sync/reports" "$fork/leankeys/LeanKeysKit/Resources"
  cp "$src/sync/check-divergence.sh" "$fork/sync/"
  printf 'myhook\tH\n' > "$fork/sync/hooks.txt"
  print -r -- '{"gonhanh": "v1.0.165", "vikey": "v1.0.33"}' > "$fork/sync/upstream.json"
  printf 'repo\tpath\n' > "$fork/sync/ported.txt"
  touch "$fork/sync/reports/.gitkeep"
  print -r -- '{"leankeys":"1.0","gonhanh":"v1.0.165","vikey":"v1.0.33"}' > "$fork/leankeys/LeanKeysKit/Resources/Versions.json"
  printf 'sync/reports/*.md\nsync/reports/*.log\nsync/.lock\n/dist/\n' > "$fork/.gitignore"
  git -C "$fork" submodule add -q "$vk" vendor/vikey 2>/dev/null
  git -C "$fork/vendor/vikey" checkout -q v1.0.33
  git -C "$fork" add -A && git -C "$fork" commit -q -m 'LeanKeys fork'
}

# Commits a change to upstream file $1 (content $2) and tags it $3.
upstream_release() {
  print -r -- "$2" > "$up/$1"
  git -C "$up" commit -q -am "upstream $3" && git -C "$up" tag "$3"
}

vikey_release() {
  print -r -- "$2" > "$vk/$1"
  git -C "$vk" commit -q -am "vikey $3" && git -C "$vk" tag "$3"
}

# Runs sync.sh on the fork; sets $out and $rc. Extra args are passed through.
run_sync() {
  rc=0
  out="$(LEANKEYS_UPSTREAM_URL="$up" LEANKEYS_VIKEY_URL="$vk" \
    LEANKEYS_TEST_CMD="${LEANKEYS_TEST_CMD-true}" \
    "$sync_sh" --repo "$fork" --no-notify "$@" 2>&1)" || rc=$?
}

report() { cat "$fork/sync/reports/$today.md" 2>/dev/null; }
json() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

check() { # check <name> <condition-description> <command...>
  local name="$1" what="$2"; shift 2
  if "$@"; then return 0; fi
  print -r -- "FAIL $name: $what (exit $rc)"
  print -r -- "$out" | sed 's/^/    /'
  return 1
}

is_rc() { [[ "$rc" == "$1" ]]; }
no_sync_branch() { [[ -z "$(git -C "$fork" branch --list 'sync/*')" ]]; }
has_sync_branch() { [[ -n "$(git -C "$fork" branch --list "sync/$today*")" ]]; }
clean() { [[ -z "$(git -C "$fork" status --porcelain)" ]]; }
main_is() { [[ "$(git -C "$fork" rev-parse main)" == "$1" ]]; }
report_has() { [[ "$(report)" == *"$1"* ]]; }
on_main() { [[ "$(git -C "$fork" symbolic-ref --short HEAD)" == main ]]; }

test_no_new_tags_exits_0_without_branch() {
  setup none
  local before; before="$(git -C "$fork" rev-parse main)"
  run_sync --skip-build
  check $0 "exit 0" is_rc 0 &&
  check $0 "no sync/* branch" no_sync_branch &&
  check $0 "main unchanged" main_is "$before" &&
  check $0 "report written" [ -f "$fork/sync/reports/$today.md" ]
}

test_new_tag_merges_to_main() {
  setup merge
  upstream_release A 'alpha 2' v1.0.166
  run_sync --skip-build
  check $0 "exit 0" is_rc 0 &&
  check $0 "main contains v1.0.166" git -C "$fork" merge-base --is-ancestor v1.0.166 main &&
  check $0 "upstream.json gonhanh" [ "$(json "$fork/sync/upstream.json" gonhanh)" = v1.0.166 ] &&
  check $0 "Versions.json bumped" [ "$(json "$fork/leankeys/LeanKeysKit/Resources/Versions.json" leankeys)" = 1.1 ] &&
  check $0 "Versions.json gonhanh" [ "$(json "$fork/leankeys/LeanKeysKit/Resources/Versions.json" gonhanh)" = v1.0.166 ] &&
  check $0 "back on main" on_main &&
  check $0 "clean tree" clean &&
  check $0 "--skip-build writes no dist/READY" [ ! -e "$fork/dist/READY" ]
}

test_conflict_aborts() {
  setup conflict
  local before; before="$(git -C "$fork" rev-parse main)"
  upstream_release H $'line 1\nhook changed upstream\nline 3' v1.0.166
  run_sync --skip-build
  check $0 "exit 2" is_rc 2 &&
  check $0 "main unchanged" main_is "$before" &&
  check $0 "no merge in progress" [ ! -e "$fork/.git/MERGE_HEAD" ] &&
  check $0 "clean tree" clean &&
  check $0 "back on main" on_main &&
  check $0 "report has CONFLICT" report_has CONFLICT
}

test_failing_tests_keep_main() {
  setup failing
  local before; before="$(git -C "$fork" rev-parse main)"
  upstream_release A 'alpha 2' v1.0.166
  vikey_release App/Core/VikeyCore.mm 'core v2' v1.0.34
  LEANKEYS_TEST_CMD=false run_sync --skip-build
  check $0 "exit 3" is_rc 3 &&
  check $0 "main unchanged" main_is "$before" &&
  check $0 "sync/$today kept" has_sync_branch &&
  check $0 "clean tree (submodule restored)" clean &&
  check $0 "back on main" on_main &&
  check $0 "upstream.json unchanged" [ "$(json "$fork/sync/upstream.json" gonhanh)" = v1.0.165 ]
}

test_lock_prevents_overlap() {
  setup lock
  sleep 300 &
  sleeper=$!
  print -r -- "$sleeper" > "$fork/sync/.lock"
  upstream_release A 'alpha 2' v1.0.166
  run_sync --skip-build
  check $0 "exit 4" is_rc 4 &&
  check $0 "lock kept" [ "$(cat "$fork/sync/.lock")" = "$sleeper" ] &&
  check $0 "no sync/* branch" no_sync_branch
  local r=$?
  kill "$sleeper" 2>/dev/null; sleeper=""
  return $r
}

test_stale_lock_is_taken_over() {
  setup stale
  sh -c 'exit 0' &
  local dead=$!
  wait "$dead"
  print -r -- "$dead" > "$fork/sync/.lock"
  run_sync --skip-build
  check $0 "exit 0" is_rc 0 &&
  check $0 "lock removed after run" [ ! -e "$fork/sync/.lock" ]
}

test_ported_file_change_reported() {
  setup ported
  printf 'repo\tpath\nvikey\tApp/Core/VikeyCore.mm\n' > "$fork/sync/ported.txt"
  git -C "$fork" commit -q -am 'port VikeyCore.mm'
  vikey_release App/Core/VikeyCore.mm 'core v2' v1.0.34
  run_sync --skip-build
  check $0 "exit 0" is_rc 0 &&
  check $0 "report has Cần chuyển tay" report_has 'Cần chuyển tay' &&
  check $0 "report has the diff" report_has '+core v2' &&
  check $0 "submodule at v1.0.34" [ "$(git -C "$fork/vendor/vikey" rev-parse HEAD)" = "$(git -C "$vk" rev-parse v1.0.34)" ] &&
  check $0 "upstream.json vikey" [ "$(json "$fork/sync/upstream.json" vikey)" = v1.0.34 ] &&
  check $0 "clean tree" clean
}

# Vikey still carries 2019 tags (v1.2.3) numbered above the current v1.0.x
# line; a higher tag that does not descend from the pinned one is not an update.
test_unrelated_higher_tag_ignored() {
  setup unrelated
  git -C "$vk" checkout -q --orphan old
  printf 'old core\n' > "$vk/App/Core/VikeyCore.mm"
  git -C "$vk" add -A && git -C "$vk" commit -q -m 'old history'
  git -C "$vk" tag v1.2.3
  git -C "$vk" checkout -q main
  run_sync --skip-build
  check $0 "exit 0" is_rc 0 &&
  check $0 "no sync/* branch" no_sync_branch &&
  check $0 "upstream.json vikey unchanged" [ "$(json "$fork/sync/upstream.json" vikey)" = v1.0.33 ]
}

test_build_writes_ready() {
  setup build
  mkdir -p "$fork/leankeys"
  cat > "$fork/leankeys/build.sh" <<'EOF'
#!/bin/zsh
# Stub: records its arguments and writes the DMG name build.sh would write.
[[ "$1" == --version && "$3" == --dmg ]] || exit 9
mkdir -p dist && print -r -- "$*" > dist/args && touch "dist/LeanKeys-$2.dmg"
EOF
  chmod +x "$fork/leankeys/build.sh"
  git -C "$fork" add -A && git -C "$fork" commit -q -m 'stub build'
  upstream_release A 'alpha 2' v1.0.166
  run_sync
  check $0 "exit 0" is_rc 0 &&
  check $0 "dist/READY = 1.1" [ "$(cat "$fork/dist/READY" 2>/dev/null)" = 1.1 ] &&
  check $0 "DMG built" [ -f "$fork/dist/LeanKeys-1.1.dmg" ]
}

test_missing_default_test_cmd_exits_3() {
  setup notest
  local before; before="$(git -C "$fork" rev-parse main)"
  upstream_release A 'alpha 2' v1.0.166
  rc=0
  out="$(unset LEANKEYS_TEST_CMD; LEANKEYS_UPSTREAM_URL="$up" LEANKEYS_VIKEY_URL="$vk" \
    "$sync_sh" --repo "$fork" --no-notify --skip-build 2>&1)" || rc=$?
  check $0 "exit 3" is_rc 3 &&
  check $0 "names .githooks/pre-push" [ "${out}" != "${out/.githooks\/pre-push/}" ] &&
  check $0 "main unchanged" main_is "$before"
}

for t in test_no_new_tags_exits_0_without_branch test_new_tag_merges_to_main \
  test_conflict_aborts test_failing_tests_keep_main test_lock_prevents_overlap \
  test_stale_lock_is_taken_over test_ported_file_change_reported \
  test_unrelated_higher_tag_ignored test_build_writes_ready \
  test_missing_default_test_cmd_exits_3; do
  if $t; then
    passed=$((passed + 1)); print -r -- "ok   $t"
  else
    failed=$((failed + 1))
  fi
done

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
