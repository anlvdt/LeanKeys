#!/bin/zsh
# Tests for sync/release.sh and .githooks/pre-push. Nothing here reaches
# GitHub: each case works in a throwaway clone under mktemp -d whose "origin"
# is a local bare repo, with a fake `gh` and a fake `hdiutil` first on PATH
# that log their arguments. release.sh runs either with --dry-run or with
# LEANKEYS_RELEASE_ASSUME_YES=1 against the fake gh.
#
# Run: zsh tests/sync/test_release.sh

emulate -L zsh
setopt no_unset pipe_fail

src="${0:A:h:h:h}"

# Keep the user's git config (signing, hooks, templates) out of the test repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset LEANKEYS_RELEASE_ASSUME_YES LEANKEYS_TTY
# The privacy gate's real command (swift test) needs the package; the test repos are bare copies.
export LEANKEYS_PRIVACY_GATE_CMD=true

base="$(mktemp -d)"
trap '[[ -n ${KEEP:-} ]] || rm -rf "$base"' EXIT

# Fake gh: logs "gh <args>" to $FAKE_LOG. FAKE_GH_FAIL=upload makes
# `release create` fail; `repo view` fails (no such repo); `repo create`
# adds $FAKE_BARE as remote origin, as the real one would with --remote.
bin="$base/bin"
mkdir -p "$bin"
cat > "$bin/gh" <<'EOF'
#!/bin/zsh
print -r -- "gh $*" >> "$FAKE_LOG"
case "$1 ${2:-}" in
  "release create") [[ "${FAKE_GH_FAIL:-}" == upload ]] && { print -u2 "upload failed"; exit 1; } ;;
  "repo view") exit 1 ;;
  "repo create") git remote add origin "$FAKE_BARE" || exit 1 ;;
esac
exit 0
EOF
# Fake hdiutil: `attach ... -mountpoint DIR dmg` puts a LeanKeys.app in DIR.
cat > "$bin/hdiutil" <<'EOF'
#!/bin/zsh
print -r -- "hdiutil $*" >> "$FAKE_LOG"
if [[ "$1" == attach ]]; then
  mp=""
  while (( $# )); do [[ "$1" == -mountpoint ]] && mp="$2"; shift; done
  [[ -n "$mp" ]] || exit 1
  mkdir -p "$mp/LeanKeys.app/Contents/MacOS"
  print '#!/bin/sh' > "$mp/LeanKeys.app/Contents/MacOS/LeanKeys"
  chmod +x "$mp/LeanKeys.app/Contents/MacOS/LeanKeys"
  [[ -n "${FAKE_DMG_KEEP:-}" ]] && : > "$mp/LeanKeys.app/Contents/debug.keep"
fi
exit 0
EOF
# Fake codesign: `-dr - APP` prints FAKE_CODESIGN_REQ (default: a self-signed leaf requirement).
cat > "$bin/codesign" <<'FAKECS'
#!/bin/zsh
print -r -- "codesign $*" >> "$FAKE_LOG"
print -r -- "${FAKE_CODESIGN_REQ:-designated => identifier \"io.github.anlvdt.leankeys\" and certificate leaf[subject.CN] = \"LeanKeys Self-Signed\"}"
exit 0
FAKECS
chmod +x "$bin/gh" "$bin/hdiutil" "$bin/codesign"
export PATH="$bin:$PATH"

# Fail closed: never let a case reach the real gh or hdiutil.
if [[ "$(command -v gh)" != "$bin/gh" || "$(command -v hdiutil)" != "$bin/hdiutil" ]]; then
  print -r -- "FAIL fake gh/hdiutil are not first on PATH"
  exit 1
fi

passed=0
failed=0
out=""
rc=0

# Sets $repo (a clone on branch main, release.sh and the checklist copied in)
# and $bare (its origin, a local bare repo) for case $1. With "no-origin" the
# clone has no origin remote. Tags v1.0 at the first commit.
setup() {
  local d="$base/$1"
  repo="$d/repo" bare="$d/origin.git"
  mkdir -p "$d"
  export FAKE_LOG="$d/calls.log" FAKE_BARE="$bare"
  : > "$FAKE_LOG"
  mkdir -p "$repo/sync" "$repo/leankeys/LeanKeysKit/Resources"
  git -C "$repo" init -q -b main
  cp "$src/sync/release.sh" "$src/sync/manual-checklist.md" "$repo/sync/"
  print -r -- '{"leankeys":"1.0","gonhanh":"v1.0.165","vikey":"v1.0.33"}' > "$repo/leankeys/LeanKeysKit/Resources/Versions.json"
  printf '/dist/\n' > "$repo/.gitignore"
  git -C "$repo" add -A && git -C "$repo" commit -q -m 'LeanKeys 1.0'
  git -C "$repo" tag v1.0
  print -r -- '{"leankeys":"1.1","gonhanh":"v1.0.166","vikey":"v1.0.34"}' > "$repo/leankeys/LeanKeysKit/Resources/Versions.json"
  git -C "$repo" commit -q -am 'Sync Gõ Nhanh v1.0.166, Vikey v1.0.34; LeanKeys 1.1'
  git init -q --bare "$bare"
  if [[ "${2:-}" != no-origin ]]; then
    git -C "$repo" remote add origin "$bare"
    git -C "$repo" push -q origin main v1.0
  fi
}

ready() { # ready <ver>: dist/READY and an (empty) dist/LeanKeys-<ver>.dmg
  mkdir -p "$repo/dist"
  print -r -- "$1" > "$repo/dist/READY"
  : > "$repo/dist/LeanKeys-$1.dmg"
}

run_release() { # sets $out and $rc
  rc=0
  out="$(cd "$repo" && sync/release.sh "$@" </dev/null 2>&1)" || rc=$?
}

check() { # check <name> <condition-description> <command...>
  local name="$1" what="$2"; shift 2
  if "$@"; then return 0; fi
  print -r -- "FAIL $name: $what (exit $rc)"
  print -r -- "$out" | sed 's/^/    /'
  print -r -- "  calls:"; sed 's/^/    /' "$FAKE_LOG" 2>/dev/null
  return 1
}

not() { ! "$@"; }
is_rc() { [[ "$rc" == "$1" ]]; }
out_has() { [[ "$out" == *"$1"* ]]; }
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
gh_not_called() { ! grep -q '^gh ' "$FAKE_LOG"; }
nothing_called() { [[ ! -s "$FAKE_LOG" ]]; }
local_tag() { git -C "$repo" rev-parse -q --verify "refs/tags/$1" >/dev/null; }
remote_tag() { [[ -n "$(git -C "$bare" tag -l "$1")" ]]; }
has_origin() { git -C "$repo" remote get-url origin >/dev/null 2>&1; }
# out_before <a> <b>: both appear in $out, the first <a> before the first <b>.
out_before() {
  local a b; a="$(print -r -- "$out" | grep -n -m1 -F -- "$1" | cut -d: -f1)" b="$(print -r -- "$out" | grep -n -m1 -F -- "$2" | cut -d: -f1)"
  [[ -n "$a" && -n "$b" ]] && (( a < b ))
}

test_no_ready_exits_1() {
  setup noready
  run_release --dry-run
  check $0 "exit 1" is_rc 1 &&
  check $0 "says Chưa có bản sẵn sàng" out_has "Chưa có bản sẵn sàng" &&
  check $0 "nothing called" nothing_called
}

test_dry_run_prints_plan() {
  setup dryrun
  ready 1.1
  run_release --dry-run
  check $0 "exit 0" is_rc 0 &&
  check $0 "plan has gh release create v1.1" out_has "gh release create v1.1" &&
  check $0 "plan has LeanKeys-1.1.dmg" out_has "LeanKeys-1.1.dmg" &&
  check $0 "fake gh not called" gh_not_called &&
  check $0 "hdiutil not called" nothing_called &&
  check $0 "no local tag" not local_tag v1.1 &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ] &&
  check $0 "plan confirms before touching GitHub" out_before "chờ gõ yes" "actions/permissions"
}

test_privacy_gate_refuses() {
  setup privacygate
  ready 1.1
  LEANKEYS_PRIVACY_GATE_CMD=false LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 1" is_rc 1 &&
  check $0 "names the rule" out_has "PrivacyDefaultsTests" &&
  check $0 "nothing called" nothing_called &&
  check $0 "no local tag" not local_tag v1.1 &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ]
}

test_debug_keep_in_dmg_refused() {
  setup debugkeep
  ready 1.1
  FAKE_DMG_KEEP=1 LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 1" is_rc 1 &&
  check $0 "names debug.keep" out_has "debug.keep" &&
  check $0 "no local tag" not local_tag v1.1 &&
  check $0 "not pushed" not remote_tag v1.1
}

test_missing_dmg_exits_1() {
  setup nodmg
  ready 1.1
  rm "$repo/dist/LeanKeys-1.1.dmg"
  run_release --dry-run
  check $0 "exit 1" is_rc 1 &&
  check $0 "names the DMG" out_has "LeanKeys-1.1.dmg" &&
  check $0 "nothing called" nothing_called
}

test_existing_local_tag_refused() {
  setup localtag
  ready 1.1
  git -C "$repo" tag v1.1
  LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 1" is_rc 1 &&
  check $0 "says the tag exists" out_has "v1.1" &&
  check $0 "gh not called" gh_not_called &&
  check $0 "not pushed" not remote_tag v1.1 &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ]
}

test_existing_remote_tag_refused() {
  setup remotetag
  ready 1.1
  git -C "$repo" tag v1.1 && git -C "$repo" push -q origin v1.1 && git -C "$repo" tag -d v1.1 >/dev/null
  local before; before="$(git -C "$bare" rev-parse v1.1)"
  LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 1" is_rc 1 &&
  check $0 "says the tag exists on origin" out_has "origin" &&
  check $0 "no release create" not log_has "gh release create" &&
  check $0 "remote tag untouched" [ "$(git -C "$bare" rev-parse v1.1)" = "$before" ] &&
  check $0 "no local tag" not local_tag v1.1
}

test_failure_cleans_up() {
  setup failure
  ready 1.1
  FAKE_GH_FAIL=upload LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit non-zero" [ "$rc" -ne 0 ] &&
  check $0 "release create attempted" log_has "gh release create v1.1" &&
  check $0 "gh release delete v1.1 --yes" log_has "gh release delete v1.1 --yes" &&
  check $0 "reports git push --delete origin v1.1" out_has "git push --delete origin v1.1" &&
  check $0 "tag deleted on origin" not remote_tag v1.1 &&
  check $0 "local tag deleted" not local_tag v1.1 &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ]
}

test_first_release_creates_repo() {
  setup firstrun no-origin
  ready 1.1
  LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 0" is_rc 0 &&
  check $0 "gh auth status" log_has "gh auth status" &&
  check $0 "repo created" log_has "gh repo create anlvdt/LeanKeys --public --source . --remote origin" &&
  check $0 "Actions disabled" log_has "gh api -X PUT repos/anlvdt/LeanKeys/actions/permissions -F enabled=false" &&
  check $0 "DMG mounted" log_has "hdiutil attach" &&
  check $0 "DMG detached" log_has "hdiutil detach" &&
  check $0 "repo created after the DMG check and the yes" [ "$(grep -n -m1 '^hdiutil detach' "$FAKE_LOG" | cut -d: -f1)" -lt "$(grep -n -m1 '^gh repo create' "$FAKE_LOG" | cut -d: -f1)" ] &&
  check $0 "release created with the DMG" log_has "gh release create v1.1 dist/LeanKeys-1.1.dmg --title LeanKeys 1.1" &&
  check $0 "release names the repo (two remotes)" log_has "-R anlvdt/LeanKeys" &&
  check $0 "notes name the engines" log_has "v1.0.166" &&
  check $0 "notes start with how to install" log_has "Tải LeanKeys-1.1.dmg, mở ra và kéo LeanKeys vào Applications" &&
  check $0 "notes say Lõi gõ, not Engine" log_has "Lõi gõ: Gõ Nhanh" &&
  check $0 "notes have the changelog" log_has "Sync Gõ Nhanh v1.0.166" &&
  check $0 "main pushed" [ "$(git -C "$bare" rev-parse main)" = "$(git -C "$repo" rev-parse main)" ] &&
  check $0 "tag pushed at main" [ "$(git -C "$bare" rev-parse 'v1.1^{commit}')" = "$(git -C "$repo" rev-parse main)" ] &&
  check $0 "only main and v1.1 pushed" [ "$(git -C "$bare" for-each-ref --format='%(refname)' | sort | tr '\n' ' ')" = "refs/heads/main refs/tags/v1.1 " ] &&
  check $0 "READY removed" [ ! -e "$repo/dist/READY" ]
}

# First release (no origin) without a "yes": no public repo, Actions untouched (ruling R27).
test_not_confirmed_aborts() {
  setup noconfirm no-origin
  ready 1.1
  : > "$base/noconfirm/tty"   # a terminal that gives EOF (^D)
  LEANKEYS_TTY="$base/noconfirm/tty" run_release
  check $0 "exit 1" is_rc 1 &&
  check $0 "says cancelled" out_has "Đã huỷ" &&
  check $0 "no repo created" not log_has "gh repo create" &&
  check $0 "no Actions call" not log_has "actions/permissions" &&
  check $0 "no origin added" not has_origin &&
  check $0 "no tag" not local_tag v1.1 &&
  check $0 "no release" not log_has "gh release create" &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ]
}

# No terminal (LEANKEYS_TTY points at a missing file) and "yes" piped on
# stdin: release.sh must refuse rather than read the confirmation from stdin.
test_piped_yes_without_tty_refuses() {
  setup pipedyes
  ready 1.1
  rc=0
  out="$(cd "$repo" && print yes | LEANKEYS_TTY="$base/pipedyes/no-tty" sync/release.sh 2>&1)" || rc=$?
  check $0 "exit 1" is_rc 1 &&
  check $0 "says a terminal is needed" out_has "Cần terminal" &&
  check $0 "no tag" not local_tag v1.1 &&
  check $0 "nothing pushed" not remote_tag v1.1 &&
  check $0 "no release" not log_has "gh release create" &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ]
}

# With origin already set (e.g. a first run that failed after repo create),
# Actions are still disabled, and before the push (a pre-push hook in the
# clone logs "git push" into the same call log).
test_existing_origin_disables_actions_before_push() {
  setup actions
  ready 1.1
  mkdir -p "$base/actions/hooks"
  printf '#!/bin/sh\necho "git push $1" >> "$FAKE_LOG"\n' > "$base/actions/hooks/pre-push"
  chmod +x "$base/actions/hooks/pre-push"
  git -C "$repo" config core.hooksPath "$base/actions/hooks"
  LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  local put push
  put="$(grep -n -m1 -F 'gh api -X PUT repos/anlvdt/LeanKeys/actions/permissions -F enabled=false' "$FAKE_LOG" | cut -d: -f1)"
  push="$(grep -n -m1 '^git push' "$FAKE_LOG" | cut -d: -f1)"
  check $0 "exit 0" is_rc 0 &&
  check $0 "no repo create" not log_has "gh repo create" &&
  check $0 "Actions PUT called" [ -n "$put" ] &&
  check $0 "push happened" [ -n "$push" ] &&
  check $0 "PUT before push" [ "${put:-99}" -lt "${push:-0}" ] &&
  check $0 "tag pushed" remote_tag v1.1
}

# pre-push in a throwaway repo whose steps are stubs that log "$PWD <step>",
# with cargo and swift faked on PATH. Sets $repo, $bare, $FAKE_LOG.
setup_hook() {
  local d="$base/$1"
  repo="$d/repo" bare="$d/origin.git"
  mkdir -p "$d"
  export FAKE_LOG="$d/steps.log"
  : > "$FAKE_LOG"
  mkdir -p "$repo/.githooks" "$repo/core" "$repo/sync" "$repo/tests/sync" "$repo/tests/build" "$repo/tests/update" "$repo/tests/privacy" \
    "$repo/leankeys" "$repo/vendor/vikey/Tools/autoswitch" "$d/bin"
  git -C "$repo" init -q -b main
  cp "$src/.githooks/pre-push" "$repo/.githooks/"
  print -r -- '{"gonhanh": "v1.0.165", "vikey": "v1.0.33"}' > "$repo/sync/upstream.json"
  local f
  for f in vendor/vikey/Tools/autoswitch/check.sh sync/check-divergence.sh \
    tests/sync/test_check_divergence.sh tests/sync/test_sync.sh tests/sync/test_release.sh \
    tests/update/test_swap_script.sh leankeys/build.sh tests/build/test_build_output.sh \
    tests/build/test_signing_identity.sh tests/privacy/test_debug_log.sh; do
    printf '#!/bin/zsh\nprint -r -- "${PWD:t} %s $* git_dir=${GIT_DIR-unset}" >> "$FAKE_LOG"\n' "$f" > "$repo/$f"
    chmod +x "$repo/$f"
  done
  for f in cargo swift; do
    printf '#!/bin/zsh\nprint -r -- "${PWD:t} %s $*" >> "$FAKE_LOG"\n' "$f" > "$d/bin/$f"
    chmod +x "$d/bin/$f"
  done
  hookpath="$d/bin:$PATH"
  git -C "$repo" add -A && git -C "$repo" commit -q -m base
  git init -q --bare "$bare"
  git -C "$repo" remote add origin "$bare"
}

test_prepush_ignores_git_hook_args() {
  setup_hook hookargs
  git -C "$repo" config core.hooksPath .githooks
  rc=0
  out="$(cd "$repo" && PATH="$hookpath" git push origin main 2>&1)" || rc=$?
  local steps; steps="$(cat "$FAKE_LOG")"
  check $0 "push exit 0" is_rc 0 &&
  check $0 "pushed" [ "$(git -C "$bare" rev-parse main 2>/dev/null)" = "$(git -C "$repo" rev-parse main)" ] &&
  check $0 "cargo test in core/" log_has "core cargo test" &&
  check $0 "swift test at the root" log_has "repo swift test" &&
  check $0 "check.sh ran" log_has "vendor/vikey/Tools/autoswitch/check.sh" &&
  check $0 "check-divergence with the pinned tag" log_has "repo sync/check-divergence.sh v1.0.165" &&
  check $0 "sync tests ran" log_has "tests/sync/test_sync.sh" &&
  check $0 "no build without --all" not log_has "test_build_output.sh" &&
  check $0 "GIT_DIR not passed to steps" not grep -q "git_dir=[^u]" "$FAKE_LOG" &&
  check $0 "steps in order" [ "$(cut -d' ' -f2 "$FAKE_LOG" | tr '\n' ' ')" = "cargo swift vendor/vikey/Tools/autoswitch/check.sh sync/check-divergence.sh tests/sync/test_check_divergence.sh tests/sync/test_sync.sh tests/sync/test_release.sh tests/update/test_swap_script.sh tests/build/test_signing_identity.sh tests/privacy/test_debug_log.sh " ]

  # Called directly, from a subdirectory, with git's hook arguments and --all.
  : > "$FAKE_LOG"
  rc=0
  out="$(cd "$repo/tests/sync" && print 'refs/heads/main abc refs/heads/main def' |
    PATH="$hookpath" "$repo/.githooks/pre-push" origin "$bare" --all 2>&1)" || rc=$?
  check $0 "direct --all exit 0" is_rc 0 &&
  check $0 "--all runs the build test" log_has "repo tests/build/test_build_output.sh" &&
  check $0 "headers printed" out_has "[6/6]"
}

test_prepush_stops_on_failure() {
  setup_hook hookfail
  printf '#!/bin/zsh\nexit 1\n' > "$repo/sync/check-divergence.sh"
  rc=0
  out="$(cd "$repo" && PATH="$hookpath" .githooks/pre-push 2>&1)" || rc=$?
  check $0 "exit non-zero" [ "$rc" -ne 0 ] &&
  check $0 "failing step named" out_has "check-divergence" &&
  check $0 "later steps skipped" not log_has "test_sync.sh"
}

# An ad-hoc DMG (cdhash requirement) is refused before any GitHub call; the DMG is still detached.
test_adhoc_release_refused() {
  setup adhoc
  ready 1.1
  FAKE_CODESIGN_REQ='designated => cdhash H"abcdef"' LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 1" is_rc 1 &&
  check $0 "says ad-hoc" out_has "ad-hoc" &&
  check $0 "names the override" out_has "LEANKEYS_ALLOW_ADHOC_RELEASE=1" &&
  check $0 "no repo, release or push" not log_has "gh release create" &&
  check $0 "no repo created" not log_has "gh repo create" &&
  check $0 "no tag" not local_tag v1.1 &&
  check $0 "DMG detached" log_has "hdiutil detach" &&
  check $0 "READY kept" [ -f "$repo/dist/READY" ]
}

# The override publishes an ad-hoc DMG on purpose.
test_adhoc_release_override() {
  setup adhocok
  ready 1.1
  FAKE_CODESIGN_REQ='designated => cdhash H"abcdef"' LEANKEYS_ALLOW_ADHOC_RELEASE=1 LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 0" is_rc 0 &&
  check $0 "release created" log_has "gh release create v1.1"
}

# A Developer ID requirement (Apple anchor plus leaf) is accepted.
test_developer_id_release_passes() {
  setup devid
  ready 1.1
  FAKE_CODESIGN_REQ='designated => anchor apple generic and certificate leaf[subject.OU] = "TEAM123456"' LEANKEYS_RELEASE_ASSUME_YES=1 run_release
  check $0 "exit 0" is_rc 0 &&
  check $0 "release created" log_has "gh release create v1.1"
}

for t in test_no_ready_exits_1 test_dry_run_prints_plan test_privacy_gate_refuses test_debug_keep_in_dmg_refused test_missing_dmg_exits_1 \
  test_existing_local_tag_refused test_existing_remote_tag_refused \
  test_failure_cleans_up test_first_release_creates_repo test_not_confirmed_aborts \
  test_piped_yes_without_tty_refuses test_existing_origin_disables_actions_before_push \
  test_adhoc_release_refused test_adhoc_release_override test_developer_id_release_passes \
  test_prepush_ignores_git_hook_args test_prepush_stops_on_failure; do
  if $t; then
    passed=$((passed + 1)); print -r -- "ok   $t"
  else
    failed=$((failed + 1))
  fi
done

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
