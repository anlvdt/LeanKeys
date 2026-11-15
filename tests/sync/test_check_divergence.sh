#!/bin/zsh
# Tests for sync/check-divergence.sh. Each case builds a throwaway git repo
# under mktemp -d, tags the "upstream" state as v0, edits it, and runs the
# checker against v0.
#
# Run: zsh tests/sync/test_check_divergence.sh

emulate -L zsh
setopt no_unset pipe_fail

checker="${0:A:h:h:h}/sync/check-divergence.sh"

# Keep the user's git config (signing, hooks, templates) out of the test repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT

passed=0
failed=0
out=""
rc=0

# Fresh repo with an upstream file X, a LICENSE, and tag v0. Prints its path.
make_repo() {
  local repo="$base/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  printf 'one\ntwo\nthree\nfour\nfive\n' > "$repo/X"
  printf 'BSD license text\n' > "$repo/LICENSE"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m upstream
  git -C "$repo" tag v0
  mkdir -p "$repo/sync"
  print -r -- "$repo"
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -q -m change
}

# Runs the checker inside $1; sets $out and $rc.
run_check() {
  rc=0
  out="$(cd "$1" && "$checker" v0 2>&1)" || rc=$?
}

expect_rc() {
  local name="$1" want="$2"
  if [[ "$rc" == "$want" ]]; then
    return 0
  fi
  print -r -- "FAIL $name: exit $rc, want $want"
  print -r -- "$out" | sed 's/^/    /'
  return 1
}

expect_out() {
  local name="$1" needle="$2"
  if [[ "$out" == *"$needle"* ]]; then
    return 0
  fi
  print -r -- "FAIL $name: output lacks '$needle'"
  print -r -- "$out" | sed 's/^/    /'
  return 1
}

test_clean_passes() {
  local repo; repo="$(make_repo clean)"
  run_check "$repo"
  expect_rc test_clean_passes 0
}

test_hooked_line_passes() {
  local repo; repo="$(make_repo hooked)"
  # Change an existing line and add a new one, both marked.
  printf 'one\ntwo // LEANKEYS-HOOK: a\nadded // LEANKEYS-HOOK: a\nthree\nfour\nfive\n' > "$repo/X"
  printf 'a\tX\n' > "$repo/sync/hooks.txt"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_hooked_line_passes 0
}

test_unhooked_line_fails() {
  local repo; repo="$(make_repo unhooked)"
  printf 'one\ntwo\nthree\nsneaky\nfour\nfive\n' > "$repo/X"
  printf 'a\tX\n' > "$repo/sync/hooks.txt"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_unhooked_line_fails 1 &&
  expect_out test_unhooked_line_fails "X:4"
}

test_unregistered_hook_fails() {
  local repo; repo="$(make_repo unregistered)"
  printf 'one\ntwo\nthree // LEANKEYS-HOOK: b\nfour\nfive\n' > "$repo/X"
  printf 'a\tX\n' > "$repo/sync/hooks.txt"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_unregistered_hook_fails 1 &&
  expect_out test_unregistered_hook_fails "X:3"
}

test_file_allowlist() {
  local repo; repo="$(make_repo allowlist)"
  printf 'GPL license text\nwith no markers at all\n' > "$repo/LICENSE"
  printf 'FILE\tLICENSE\n' > "$repo/sync/hooks.txt"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_file_allowlist 0
}

test_new_files_ignored() {
  local repo; repo="$(make_repo newfiles)"
  printf 'brand new\nno markers\n' > "$repo/Y"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_new_files_ignored 0
}

# Extra: a BEGIN/END block covers the unmarked lines inside it.
test_hook_block_passes() {
  local repo; repo="$(make_repo block)"
  printf 'one\n// LEANKEYS-HOOK-BEGIN: a\nplain\nlines\n// LEANKEYS-HOOK-END\ntwo\nthree\nfour\nfive\n' > "$repo/X"
  printf 'a\tX\n' > "$repo/sync/hooks.txt"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_hook_block_passes 0
}

# Extra: a block with no END covers nothing.
test_unterminated_block_fails() {
  local repo; repo="$(make_repo unterminated)"
  printf 'one\n// LEANKEYS-HOOK-BEGIN: a\nplain\ntwo\nthree\nfour\nfive\n' > "$repo/X"
  printf 'a\tX\n' > "$repo/sync/hooks.txt"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_unterminated_block_fails 1 &&
  expect_out test_unterminated_block_fails "X:3"
}

# Extra: deleting upstream lines with nothing hooked in their place fails.
test_pure_deletion_fails() {
  local repo; repo="$(make_repo deletion)"
  printf 'one\ntwo\nfive\n' > "$repo/X"
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_pure_deletion_fails 1 &&
  expect_out test_pure_deletion_fails "X:2"
}

# Deleting an upstream file is a divergence.
test_deleted_upstream_file_fails() {
  local repo; repo="$(make_repo deleted)"
  git -C "$repo" rm -q X
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_deleted_upstream_file_fails 1 &&
  expect_out test_deleted_upstream_file_fails "X:0: upstream file deleted"
}

# A rename shows as deletion of the old path.
test_renamed_upstream_file_fails() {
  local repo; repo="$(make_repo renamed)"
  git -C "$repo" mv X Z
  commit_all "$repo"
  run_check "$repo"
  expect_rc test_renamed_upstream_file_fails 1 &&
  expect_out test_renamed_upstream_file_fails "X:0: upstream file deleted"
}

# If git diff itself fails (here: a corrupt index), the gate fails closed.
test_git_failure_fails_closed() {
  local repo; repo="$(make_repo gitfail)"
  print -r -- garbage > "$repo/.git/index"
  run_check "$repo"
  expect_rc test_git_failure_fails_closed 2 &&
  expect_out test_git_failure_fails_closed "check-divergence: git diff failed"
}

for t in test_clean_passes test_hooked_line_passes test_unhooked_line_fails \
         test_unregistered_hook_fails test_file_allowlist test_new_files_ignored \
         test_hook_block_passes test_unterminated_block_fails test_pure_deletion_fails \
         test_deleted_upstream_file_fails test_renamed_upstream_file_fails \
         test_git_failure_fails_closed; do
  if ( $t ); then
    print -r -- "PASS $t"
    (( passed++ )) || true
  else
    (( failed++ )) || true
  fi
done

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
