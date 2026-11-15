#!/bin/zsh
# Usage: sync/sync.sh [--repo DIR] [--no-notify] [--skip-build]
#
# Daily upstream sync (spec §5.2). Looks for a newer Gõ Nhanh tag (remote
# "upstream") and a newer Vikey tag (submodule vendor/vikey) than the ones in
# sync/upstream.json. If there is one: branch sync/<YYYY-MM-DD> off main,
# merge the Gõ Nhanh tag, move vendor/vikey to the Vikey tag, run
# check-divergence.sh, report changes to hand-ported files (sync/ported.txt),
# bump the LeanKeys minor version, run the tests, build the DMG, and
# fast-forward main. Main only moves when everything passed. Never pushes.
#
#   --repo DIR     repository to sync (default: the one holding this script)
#   --no-notify    no macOS notifications
#   --skip-build   merge, test and update main, but build nothing and write no dist/READY
#
# Exit: 0 nothing new, or synced (with --skip-build) / build ready in
#       dist/LeanKeys-<ver>.dmg with <ver> in dist/READY
#       1 other error (dirty tree, fetch failed, missing branch)
#       2 merge conflict (merge aborted, main unchanged)
#       3 divergence, test or build failure (sync branch kept, main unchanged)
#       4 another run holds sync/.lock
# Report: sync/reports/<YYYY-MM-DD>.md (appended per run).
#
# Environment:
#   LEANKEYS_MAIN_BRANCH   branch to sync into (default: main)
#   LEANKEYS_TEST_CMD      test command run in the repo (default: .githooks/pre-push --all)
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
typeset -g orig="" branch="" main_branch=""

release_lock() {
  [[ -n "$lock" && -f "$lock" && "$(<"$lock")" == "$$" ]] && rm -f "$lock"
}
trap release_lock EXIT

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

# Back to the branch the run started on, with the submodule at its pin.
restore() {
  [[ -n "$orig" ]] || return 0
  g checkout -q -f "$orig" 2>/dev/null
  g submodule update -q --init 2>/dev/null
}

# fail <code> <message>: report, restore, keep the sync branch, notify, exit.
fail() {
  local code="$1"; shift
  say ""
  say "**Lỗi (mã $code):** $*"
  restore
  if [[ -n "$branch" ]]; then
    say "Nhánh \`$branch\` được giữ lại để xem; \`$main_branch\` không đổi."
  fi
  notify "Đồng bộ lỗi: $* — xem $report"
  exit "$code"
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

main() {
  while (( $# )); do
    case "$1" in
      --repo) (( $# >= 2 )) || { print -u2 "sync.sh: --repo needs a value"; exit 1; }
              repo="$2"; shift 2 ;;
      --no-notify) notify=0; shift ;;
      --skip-build) skip_build=1; shift ;;
      -h|--help) sed -n '2,30p' "$self"; exit 0 ;;
      *) print -u2 "sync.sh: unknown argument: $1"; exit 1 ;;
    esac
  done
  [[ -n "$repo" ]] || repo="${self:h:h}"
  repo="${repo:A}"
  main_branch="${LEANKEYS_MAIN_BRANCH:-main}"

  [[ "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" == "$repo" ]] ||
    { print -u2 "sync.sh: not a git repository root: $repo"; exit 1; }

  local today; today="$(date +%F)"
  mkdir -p "$repo/sync/reports"
  report="$repo/sync/reports/$today.md"
  [[ -s "$report" ]] || print -r -- "# Đồng bộ upstream $today" > "$report"
  say ""
  say "## Lần chạy $(date +%T)"
  say ""

  take_lock

  g rev-parse -q --verify "refs/heads/$main_branch" >/dev/null ||
    fail 1 "không có nhánh $main_branch"
  [[ -z "$(g status --porcelain --untracked-files=no)" ]] ||
    fail 1 "cây làm việc có thay đổi chưa commit"

  local state="$repo/sync/upstream.json"
  local cur_g cur_v
  cur_g="$(json_get "$state" gonhanh)" && cur_v="$(json_get "$state" vikey)" ||
    fail 1 "không đọc được $state"

  # Gõ Nhanh tags.
  local up_url="${LEANKEYS_UPSTREAM_URL:-}"
  [[ -n "$up_url" ]] || up_url="$(g remote get-url upstream 2>/dev/null)" ||
    up_url="https://github.com/khaphanspace/gonhanh.org.git"
  g fetch -q --no-tags "$up_url" 'refs/tags/v*:refs/tags/v*' ||
    fail 1 "không fetch được tag Gõ Nhanh từ $up_url"
  g rev-parse -q --verify "refs/tags/$cur_g" >/dev/null || fail 1 "không có tag Gõ Nhanh $cur_g"
  local new_g; new_g="$(newest_after "$repo" "$cur_g")"

  # Vikey tags, in the submodule.
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

  # Sync branch off main.
  orig="$(g symbolic-ref -q --short HEAD || g rev-parse HEAD)"
  branch="sync/$today"
  local n=2
  while g rev-parse -q --verify "refs/heads/$branch" >/dev/null; do
    branch="sync/$today-$n"; n=$((n + 1))
  done
  g checkout -q -b "$branch" "$main_branch" && g submodule update -q --init ||
    { branch=""; fail 1 "không tạo được nhánh sync"; }
  say "- Nhánh: \`$branch\`"

  # Merge Gõ Nhanh.
  if [[ -n "$new_g" ]]; then
    local out
    if ! out="$(g merge --no-ff --no-edit -m "Merge Gõ Nhanh $new_g" "refs/tags/$new_g" 2>&1)"; then
      local conflicted; conflicted="$(g diff --name-only --diff-filter=U)"
      g merge --abort 2>/dev/null
      restore
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
    git -C "$sub" checkout -q --detach "refs/tags/$new_v" ||
      fail 1 "không checkout được Vikey $new_v"
    g add vendor/vikey && g commit -q -m "Update Vikey to $new_v" ||
      fail 1 "không commit được submodule Vikey"
    say "- vendor/vikey → $new_v."
  fi

  # Divergence from Gõ Nhanh.
  local div
  if ! div="$(cd "$repo" && zsh sync/check-divergence.sh "$g_tag" 2>&1)"; then
    say ""
    say "## Sửa file gốc ngoài các hook đã đăng ký"
    say ""
    print -r -- "$div" | block ""
    fail 3 "check-divergence.sh $g_tag báo lỗi"
  fi
  say "- check-divergence.sh $g_tag: sạch."

  # Hand-ported files whose upstream source changed.
  local ported="$repo/sync/ported.txt" line prepo ppath d
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
  local vfile="$repo/leankeys/LeanKeysKit/Resources/Versions.json" old_ver ver
  old_ver="$(json_get "$vfile" leankeys)" || fail 1 "không đọc được $vfile"
  [[ "$old_ver" == <->.<-> ]] || fail 1 "phiên bản LeanKeys không dạng X.Y: $old_ver"
  ver="${old_ver%%.*}.$(( ${old_ver#*.} + 1 ))"
  print -r -- "{\"gonhanh\": \"$g_tag\", \"vikey\": \"$v_tag\"}" > "$state"
  print -r -- "{\"leankeys\":\"$ver\",\"gonhanh\":\"$g_tag\",\"vikey\":\"$v_tag\"}" > "$vfile"
  g add sync/upstream.json leankeys/LeanKeysKit/Resources/Versions.json &&
    g commit -q -m "Sync Gõ Nhanh $g_tag, Vikey $v_tag; LeanKeys $ver" ||
    fail 1 "không commit được upstream.json/Versions.json"
  say "- LeanKeys $old_ver → $ver."

  # Tests.
  local test_cmd="${LEANKEYS_TEST_CMD:-}"
  if [[ -z "$test_cmd" ]]; then
    [[ -x "$repo/.githooks/pre-push" ]] ||
      fail 3 "thiếu .githooks/pre-push (lệnh test mặc định); đặt LEANKEYS_TEST_CMD hoặc thêm hook"
    test_cmd=".githooks/pre-push --all"
  fi
  say "- Test: \`$test_cmd\`"
  local tout trc=0
  tout="$(cd "$repo" && eval "$test_cmd" 2>&1)" || trc=$?
  if (( trc )); then
    say ""
    say "## Test lỗi (mã $trc)"
    say ""
    print -r -- "$tout" | tail -n 200 | block ""
    fail 3 "test lỗi: $test_cmd"
  fi
  say "- Test đạt."

  # Build on the sync branch, so a failed build leaves main untouched.
  if (( ! skip_build )); then
    local bout brc=0
    bout="$(cd "$repo" && leankeys/build.sh --version "$ver" --dmg 2>&1)" || brc=$?
    if (( brc )) || [[ ! -f "$repo/dist/LeanKeys-$ver.dmg" ]]; then
      say ""
      say "## Build lỗi (mã $brc)"
      say ""
      print -r -- "$bout" | tail -n 200 | block ""
      fail 3 "build lỗi"
    fi
    say "- Đã build dist/LeanKeys-$ver.dmg."
  fi

  # Fast-forward main.
  g checkout -q -f "$main_branch" && g merge -q --ff-only "$branch" ||
    fail 1 "không fast-forward được $main_branch"
  g branch -q -d "$branch"
  local merged="$branch"
  branch=""
  if [[ "$orig" != "$main_branch" ]]; then
    restore
  else
    g submodule update -q --init
  fi
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
