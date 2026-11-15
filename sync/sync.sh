#!/bin/zsh
# Usage: sync/sync.sh [--repo DIR] [--no-notify] [--skip-build]
#
# Daily upstream sync (spec §5.2). Looks for a newer Gõ Nhanh tag (remote
# "upstream") and a newer Vikey tag (submodule vendor/vikey) than the ones in
# sync/upstream.json. If there is one, it works in a private worktree at
# <repo>/.sync-worktree on branch sync/<YYYY-MM-DD> off main: merges the Gõ
# Nhanh tag, moves vendor/vikey to the Vikey tag, runs check-divergence.sh,
# reports changes to hand-ported files (sync/ported.txt), bumps the LeanKeys
# minor version, runs the tests and builds the DMG. Only when all of that
# passed does main move, without touching the user's checkout beyond a
# fast-forward: `merge --ff-only` where main is checked out, otherwise
# `update-ref`. The user's checkout is never switched, reset or
# force-checked-out. Never pushes.
#
#   --repo DIR     repository to sync (default: the one holding this script)
#   --no-notify    no macOS notifications
#   --skip-build   merge, test and update main, but build nothing and write no dist/READY
#
# Exit: 0 nothing new, or synced (with --skip-build) / build ready in
#       dist/LeanKeys-<ver>.dmg with <ver> in dist/READY
#       1 other error (fetch failed, missing branch)
#       2 merge conflict (sync branch deleted, main unchanged)
#       3 divergence, test or build failure, or main could not be
#         fast-forwarded (sync branch kept, main unchanged)
#       4 another run holds sync/.lock
#       128+N killed by signal N (worktree removed, lock released)
# Report: sync/reports/<YYYY-MM-DD>.md (appended per run).
#
# Environment:
#   LEANKEYS_MAIN_BRANCH   branch to sync into (default: main)
#   LEANKEYS_TEST_CMD      test command, run in the worktree (default: .githooks/pre-push --all)
#   LEANKEYS_UPSTREAM_URL  Gõ Nhanh repo (default: remote "upstream", else GitHub)
#   LEANKEYS_VIKEY_URL     Vikey repo (default: the submodule's origin, else GitHub)
#
# A tag counts as newer only when it is a strict descendant of the pinned tag:
# Vikey still carries 2019 tags (v1.2.x) that sort above the current v1.0.x.

emulate -L zsh
setopt no_unset pipe_fail

# Script path, captured before main() (inside a function $0 is its name).
typeset -g self="${0:A}"
typeset -g repo="" lock="" report="" notify=1 skip_build=0
typeset -g wt="" wt_ours=0 branch="" main_branch="" child=""

say() {
  print -r -- "$*"
  [[ -n "$report" ]] && print -r -- "$*" >> "$report"
}

# Appends a fenced block (stdin) to the report and echoes it to stdout.
block() {
  local lang="$1" text
  text="$(cat)"
  print -r -- "$text"
  [[ -n "$report" ]] && print -r -- $'```'"$lang"$'\n'"$text"$'\n```' >> "$report"
}

notify() {
  (( notify )) || return 0
  local msg="${1//\"/\\\"}"
  osascript -e "display notification \"$msg\" with title \"LeanKeys\"" >/dev/null 2>&1 || true
}

g() { git -C "$repo" "$@"; }
w() { git -C "$wt" "$@"; }

# Removes exactly <repo>/.sync-worktree, registered or not.
remove_worktree() {
  [[ -n "$repo" && "$wt" == "$repo/.sync-worktree" ]] || return 0
  if [[ -e "$wt" ]]; then
    g worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf -- "$wt"
  fi
  g worktree prune 2>/dev/null
  wt_ours=0
}

release_lock() {
  [[ -n "$lock" && -f "$lock" && "$(<"$lock" 2>/dev/null)" == "$$" ]] && rm -f "$lock"
}

cleanup() {
  if [[ -n "$child" ]]; then
    pkill -TERM -P "$child" 2>/dev/null
    kill -TERM "$child" 2>/dev/null
    child=""
  fi
  (( wt_ours )) && remove_worktree
  release_lock
}
trap cleanup EXIT
on_signal() {
  say ""
  say "**Bị dừng bởi tín hiệu $1.** Đã xoá worktree; \`$main_branch\` không đổi."
  cleanup
  exit $(( 128 + $2 ))
}
trap 'on_signal INT 2' INT
trap 'on_signal TERM 15' TERM
trap 'on_signal HUP 1' HUP

# fail <code> <message>: report, remove the worktree, keep the sync branch, notify, exit.
fail() {
  local code="$1"; shift
  say ""
  say "**Lỗi (mã $code):** $*"
  (( wt_ours )) && remove_worktree
  if [[ -n "$branch" ]]; then
    say "Nhánh \`$branch\` được giữ lại để xem; \`$main_branch\` không đổi."
  fi
  notify "Đồng bộ lỗi: $* — xem $report"
  exit "$code"
}

# run_bg <outfile> <dir> <command>: runs the command in the background so a
# signal trap can fire and kill it; returns its exit status.
run_bg() {
  local outfile="$1" dir="$2" cmd="$3" rc=0
  ( cd "$dir" && eval "$cmd" ) > "$outfile" 2>&1 &
  child=$!
  wait "$child" || rc=$?
  child=""
  return $rc
}

json_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# newest_after <git-dir> <pinned-tag>: highest v*.*.* tag (no -pre) that is a
# strict descendant of the pinned tag; prints nothing when there is none.
newest_after() {
  local dir="$1" pinned="$2" t
  for t in ${(f)"$(git -C "$dir" tag -l 'v*' --sort=-v:refname | grep -v -- '-pre' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)"}; do
    [[ "$t" == "$pinned" ]] && return 0
    if git -C "$dir" merge-base --is-ancestor "refs/tags/$pinned" "refs/tags/$t" 2>/dev/null; then
      print -r -- "$t"
      return 0
    fi
  done
}

take_lock() {
  lock="$repo/sync/.lock"
  local pid
  if ! ( setopt noclobber; print -r -- "$$" > "$lock" ) 2>/dev/null; then
    pid="$(<"$lock" 2>/dev/null)"
    if [[ "$pid" == <-> ]] && kill -0 "$pid" 2>/dev/null; then
      lock=""   # not ours; leave it
      say "Đang có lần chạy khác (PID $pid, $repo/sync/.lock). Thoát."
      exit 4
    fi
    say "Khoá cũ của PID ${pid:-?} đã hết hạn; chạy tiếp."
    print -r -- "$$" > "$lock"
  fi
}

# Path of the worktree (the user's checkout or another) that has main
# checked out, or nothing.
main_checkout() {
  local line wtpath=""
  for line in ${(f)"$(g worktree list --porcelain)"}; do
    case "$line" in
      "worktree "*) wtpath="${line#worktree }" ;;
      "branch refs/heads/$main_branch") [[ "$wtpath" != "$wt" ]] && { print -r -- "$wtpath"; return 0; } ;;
    esac
  done
}

main() {
  while (( $# )); do
    case "$1" in
      --repo) (( $# >= 2 )) || { print -u2 "sync.sh: --repo needs a value"; exit 1; }
              repo="$2"; shift 2 ;;
      --no-notify) notify=0; shift ;;
      --skip-build) skip_build=1; shift ;;
      -h|--help) sed -n '2,37p' "$self"; exit 0 ;;
      *) print -u2 "sync.sh: unknown argument: $1"; exit 1 ;;
    esac
  done
  [[ -n "$repo" ]] || repo="${self:h:h}"
  repo="${repo:A}"
  main_branch="${LEANKEYS_MAIN_BRANCH:-main}"

  [[ "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" == "$repo" ]] ||
    { print -u2 "sync.sh: not a git repository root: $repo"; exit 1; }
  wt="$repo/.sync-worktree"

  local today; today="$(date +%F)"
  mkdir -p "$repo/sync/reports"
  report="$repo/sync/reports/$today.md"
  [[ -s "$report" ]] || print -r -- "# Đồng bộ upstream $today" > "$report"
  say ""
  say "## Lần chạy $(date +%T)"
  say ""

  take_lock

  # A worktree left by a killed run; we hold the lock, so it is not live.
  if [[ -e "$wt" ]]; then
    say "- Xoá worktree còn sót từ lần chạy bị dừng: $wt"
    remove_worktree
  fi

  g rev-parse -q --verify "refs/heads/$main_branch" >/dev/null ||
    fail 1 "không có nhánh $main_branch"

  local cur_g cur_v
  cur_g="$(g show "refs/heads/${main_branch}:sync/upstream.json" | plutil -extract gonhanh raw -o - - 2>/dev/null)" &&
    cur_v="$(g show "refs/heads/${main_branch}:sync/upstream.json" | plutil -extract vikey raw -o - - 2>/dev/null)" ||
    fail 1 "không đọc được sync/upstream.json trên $main_branch"

  # Gõ Nhanh tags (refs are shared with the user's repo; only tags are added).
  local up_url="${LEANKEYS_UPSTREAM_URL:-}"
  [[ -n "$up_url" ]] || up_url="$(g remote get-url upstream 2>/dev/null)" ||
    up_url="https://github.com/khaphanspace/gonhanh.org.git"
  g fetch -q --no-tags "$up_url" 'refs/tags/v*:refs/tags/v*' ||
    fail 1 "không fetch được tag Gõ Nhanh từ $up_url"
  g rev-parse -q --verify "refs/tags/$cur_g" >/dev/null || fail 1 "không có tag Gõ Nhanh $cur_g"
  local new_g; new_g="$(newest_after "$repo" "$cur_g")"

  # Vikey tags, fetched into the user's submodule repo (tags only).
  local sub="$repo/vendor/vikey"
  [[ -e "$sub/.git" ]] || g submodule update -q --init vendor/vikey ||
    fail 1 "không khởi tạo được submodule vendor/vikey"
  local vk_url="${LEANKEYS_VIKEY_URL:-}"
  [[ -n "$vk_url" ]] || vk_url="$(git -C "$sub" remote get-url origin 2>/dev/null)" ||
    vk_url="https://github.com/tonyminibot/Vikey.git"
  git -C "$sub" fetch -q --no-tags "$vk_url" 'refs/tags/v*:refs/tags/v*' ||
    fail 1 "không fetch được tag Vikey từ $vk_url"
  git -C "$sub" rev-parse -q --verify "refs/tags/$cur_v" >/dev/null || fail 1 "không có tag Vikey $cur_v"
  local new_v; new_v="$(newest_after "$sub" "$cur_v")"

  say "- Gõ Nhanh: $cur_g → ${new_g:-(không có tag mới)}"
  say "- Vikey: $cur_v → ${new_v:-(không có tag mới)}"

  if [[ -z "$new_g" && -z "$new_v" ]]; then
    say ""
    say "Không có tag mới. Không làm gì."
    exit 0
  fi
  local g_tag="${new_g:-$cur_g}" v_tag="${new_v:-$cur_v}"

  # Private worktree on a new sync branch off main.
  local main_old; main_old="$(g rev-parse "refs/heads/$main_branch")"
  branch="sync/$today"
  local n=2
  while g rev-parse -q --verify "refs/heads/$branch" >/dev/null; do
    branch="sync/$today-$n"; n=$((n + 1))
  done
  wt_ours=1
  g worktree add -q -b "$branch" "$wt" "$main_old" 2>/dev/null ||
    { branch=""; fail 1 "không tạo được worktree $wt"; }
  local -a ref=()
  [[ -e "$sub/.git" ]] && ref=(--reference "$sub")
  w submodule update -q --init "${ref[@]}" ||
    fail 1 "không khởi tạo được submodule trong worktree"
  say "- Nhánh: \`$branch\` (worktree \`.sync-worktree\`)"

  # Merge Gõ Nhanh.
  if [[ -n "$new_g" ]]; then
    local out
    if ! out="$(w merge --no-ff --no-edit -m "Merge Gõ Nhanh $new_g" "refs/tags/$new_g" 2>&1)"; then
      local conflicted; conflicted="$(w diff --name-only --diff-filter=U)"
      w merge --abort 2>/dev/null
      remove_worktree
      g branch -q -D "$branch" 2>/dev/null
      branch=""
      if [[ -n "$conflicted" ]]; then
        say ""
        say "## CONFLICT khi merge Gõ Nhanh $new_g"
        say ""
        say "Đã \`git merge --abort\`; \`$main_branch\` không đổi. File xung đột:"
        say ""
        print -r -- "$conflicted" | block ""
        print -r -- "$out" | block ""
        notify "Xung đột merge Gõ Nhanh $new_g — xem $report"
        exit 2
      fi
      print -r -- "$out" | block ""
      fail 1 "merge Gõ Nhanh $new_g lỗi (không phải xung đột)"
    fi
    say "- Đã merge Gõ Nhanh $new_g."
  fi

  # Move Vikey.
  if [[ -n "$new_v" ]]; then
    local vsha; vsha="$(git -C "$sub" rev-parse "refs/tags/$new_v^{commit}")"
    git -C "$wt/vendor/vikey" checkout -q --detach "$vsha" 2>/dev/null ||
      { git -C "$wt/vendor/vikey" fetch -q "$vk_url" "refs/tags/$new_v" &&
        git -C "$wt/vendor/vikey" checkout -q --detach "$vsha"; } ||
      fail 1 "không checkout được Vikey $new_v"
    w add vendor/vikey && w commit -q -m "Update Vikey to $new_v" ||
      fail 1 "không commit được submodule Vikey"
    say "- vendor/vikey → $new_v."
  fi

  # Divergence from Gõ Nhanh.
  local div
  if ! div="$(cd "$wt" && zsh sync/check-divergence.sh "$g_tag" 2>&1)"; then
    say ""
    say "## Sửa file gốc ngoài các hook đã đăng ký"
    say ""
    print -r -- "$div" | block ""
    fail 3 "check-divergence.sh $g_tag báo lỗi"
  fi
  say "- check-divergence.sh $g_tag: sạch."

  # Hand-ported files whose upstream source changed.
  local ported="$wt/sync/ported.txt" line prepo ppath d
  local -a todo=()
  if [[ -f "$ported" ]]; then
    for line in ${(f)"$(<"$ported")"}; do
      [[ -z "$line" || "$line" == \#* || "$line" == $'repo\tpath' ]] && continue
      prepo="${line%%$'\t'*}" ppath="${line#*$'\t'}"
      d=""
      case "$prepo" in
        vikey) [[ -n "$new_v" ]] && d="$(git -C "$sub" diff "refs/tags/$cur_v" "refs/tags/$new_v" -- "$ppath")" ;;
        gonhanh) [[ -n "$new_g" ]] && d="$(g diff "refs/tags/$cur_g" "refs/tags/$new_g" -- "$ppath")" ;;
        *) todo+=("- $prepo/$ppath: chưa theo dõi được repo \`$prepo\`, kiểm tra tay.") ;;
      esac
      [[ -n "$d" ]] && todo+=("### $prepo: $ppath" "$d")
    done
  fi
  if (( ${#todo} )); then
    say ""
    say "## Cần chuyển tay"
    say ""
    local i=1
    while (( i <= ${#todo} )); do
      if [[ "${todo[i]}" == '### '* ]]; then
        say "${todo[i]}"; say ""
        print -r -- "${todo[i+1]}" | block diff
        i=$((i + 2))
      else
        say "${todo[i]}"; i=$((i + 1))
      fi
    done
  fi

  # New version and upstream state, committed on the sync branch.
  local vfile="$wt/leankeys/LeanKeysKit/Resources/Versions.json" old_ver ver
  old_ver="$(json_get "$vfile" leankeys)" || fail 1 "không đọc được Versions.json"
  [[ "$old_ver" == <->.<-> ]] || fail 1 "phiên bản LeanKeys không dạng X.Y: $old_ver"
  ver="${old_ver%%.*}.$(( ${old_ver#*.} + 1 ))"
  print -r -- "{\"gonhanh\": \"$g_tag\", \"vikey\": \"$v_tag\"}" > "$wt/sync/upstream.json"
  print -r -- "{\"leankeys\":\"$ver\",\"gonhanh\":\"$g_tag\",\"vikey\":\"$v_tag\"}" > "$vfile"
  w add sync/upstream.json leankeys/LeanKeysKit/Resources/Versions.json &&
    w commit -q -m "Sync Gõ Nhanh $g_tag, Vikey $v_tag; LeanKeys $ver" ||
    fail 1 "không commit được upstream.json/Versions.json"
  say "- LeanKeys $old_ver → $ver."

  # Tests, in the worktree.
  local test_cmd="${LEANKEYS_TEST_CMD:-}"
  if [[ -z "$test_cmd" ]]; then
    [[ -x "$wt/.githooks/pre-push" ]] ||
      fail 3 "thiếu .githooks/pre-push (lệnh test mặc định); đặt LEANKEYS_TEST_CMD hoặc thêm hook"
    test_cmd=".githooks/pre-push --all"
  fi
  say "- Test: \`$test_cmd\`"
  local tmpout; tmpout="$(mktemp -t leankeys-sync)"
  local trc=0
  run_bg "$tmpout" "$wt" "$test_cmd" || trc=$?
  if (( trc )); then
    say ""
    say "## Test lỗi (mã $trc)"
    say ""
    tail -n 200 "$tmpout" | block ""
    rm -f "$tmpout"
    fail 3 "test lỗi: $test_cmd"
  fi
  say "- Test đạt."

  # Build in the worktree.
  if (( ! skip_build )); then
    local brc=0
    run_bg "$tmpout" "$wt" "LEANKEYS_REQUIRE_STABLE_SIGNING=1 leankeys/build.sh --version '$ver' --dmg" || brc=$?
    if (( brc )) || [[ ! -f "$wt/dist/LeanKeys-$ver.dmg" ]]; then
      say ""
      say "## Build lỗi (mã $brc)"
      say ""
      tail -n 200 "$tmpout" | block ""
      rm -f "$tmpout"
      fail 3 "build lỗi"
    fi
    say "- Đã build LeanKeys-$ver.dmg."
  fi
  rm -f "$tmpout"

  # Advance main without switching anyone's checkout.
  local new; new="$(w rev-parse HEAD)"
  local co; co="$(main_checkout)"
  if [[ -n "$co" ]]; then
    local mout
    if ! mout="$(git -C "$co" merge -q --ff-only "$branch" 2>&1)"; then
      say ""
      say "## Không fast-forward được \`$main_branch\`"
      say ""
      say "\`git merge --ff-only $branch\` trong \`$co\` bị từ chối (thay đổi cục bộ sẽ bị ghi đè, hoặc \`$main_branch\` đã đổi). Không đụng vào thay đổi của bạn."
      print -r -- "$mout" | block ""
      fail 3 "không fast-forward được $main_branch"
    fi
    # Move the submodule along only if it sat untouched at the old pin.
    local cosub="$co/vendor/vikey"
    if [[ -n "$new_v" && -e "$cosub/.git" ]]; then
      local oldpin; oldpin="$(git -C "$co" rev-parse "${main_old}:vendor/vikey" 2>/dev/null)"
      if [[ "$(git -C "$cosub" rev-parse HEAD 2>/dev/null)" == "$oldpin" &&
            -z "$(git -C "$cosub" status --porcelain 2>/dev/null)" ]]; then
        git -C "$co" submodule update -q vendor/vikey
      else
        say "- vendor/vikey trong \`$co\` có thay đổi; không cập nhật, chạy \`git submodule update\` khi sẵn sàng."
      fi
    fi
  else
    g update-ref -m "sync.sh: $branch" "refs/heads/$main_branch" "$new" "$main_old" ||
      fail 3 "$main_branch đã đổi trong lúc chạy; không cập nhật"
  fi

  # Artifacts out of the worktree before it goes.
  if (( ! skip_build )); then
    mkdir -p "$repo/dist" && cp "$wt/dist/LeanKeys-$ver.dmg" "$repo/dist/" ||
      fail 1 "không copy được LeanKeys-$ver.dmg vào dist/"
  fi
  remove_worktree
  g branch -q -D "$branch"   # main now contains it
  local merged="$branch"
  branch=""
  say "- \`$main_branch\` đã có \`$merged\`; đã xoá nhánh sync."

  if (( skip_build )); then
    say ""
    say "Đã đồng bộ LeanKeys $ver (--skip-build: không build, không ghi dist/READY)."
    notify "Đã đồng bộ LeanKeys $ver (chưa build)"
  else
    print -r -- "$ver" > "$repo/dist/READY"
    say ""
    say "Bản LeanKeys $ver sẵn sàng: dist/LeanKeys-$ver.dmg. Chạy release.sh để đăng."
    notify "Bản LeanKeys $ver sẵn sàng — chạy release.sh để đăng"
  fi
  exit 0
}

main "$@"
