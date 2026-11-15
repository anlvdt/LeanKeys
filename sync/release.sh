#!/bin/zsh
# Usage: sync/release.sh [--dry-run]
#
# Publishes the build that sync/sync.sh (or leankeys/build.sh --dmg) left in
# dist/ as a GitHub release of anlvdt/LeanKeys (spec §5.3). You run it; no job
# does. The version comes from dist/READY. Steps:
#   1. gh auth status
#   2. mounts the DMG read-only and checks it holds LeanKeys.app, then detaches
#   3. prints sync/manual-checklist.md and waits for you to type "yes"
#   4. only after that "yes" (ruling R27): no remote "origin": gh repo create
#      anlvdt/LeanKeys --public --source . --remote origin (if the GitHub repo
#      already exists, origin is just added). Then, on every run, disables
#      GitHub Actions on it (the Gõ Nhanh workflows came along): gh api -X PUT
#      .../actions/permissions -F enabled=false, which is idempotent and runs
#      before anything is pushed.
#   5. git tag vX.Y on main; git push origin main vX.Y (only those two refs,
#      never --force, never --tags)
#   6. gh release create vX.Y dist/LeanKeys-X.Y.dmg, notes generated from
#      Versions.json on main and git log since the previous LeanKeys tag
#   7. removes dist/READY
# Refuses (exit 1) before doing anything when dist/READY or the DMG is
# missing, the version on main differs from dist/READY, or tag vX.Y already
# exists locally or on origin. If step 5 or 6 fails (or you press ^C), it runs
# `gh release delete vX.Y --yes`, `git push --delete origin vX.Y` and
# `git tag -d vX.Y`, keeps dist/READY and exits 1. A main already pushed stays
# pushed (undoing it would need --force).
#
#   --dry-run   check dist/ and the tag, print the plan and the release notes;
#               calls no gh, mounts nothing, creates and pushes nothing
#
# Always tags and pushes branch main. Confirmation is read only from
# /dev/tty, never from stdin: without a terminal it refuses (exit 1).
#
# Environment (tests only, never for a real release):
#   LEANKEYS_RELEASE_ASSUME_YES   1 skips the "yes" prompt (with a fake gh)
#   LEANKEYS_TTY                  file to read the confirmation from instead
#                                 of /dev/tty (to simulate "no terminal")
#
# Exit: 0 published (or --dry-run plan printed), 1 refused, cancelled or failed.

emulate -L zsh
setopt no_unset pipe_fail

typeset -g self="${0:A}"
typeset -g repo="${self:h:h}" gh_repo="anlvdt/LeanKeys"
typeset -g main_branch=main
typeset -g tag="" tagged=0 mnt="" attached=0

die() { print -u2 -r -- "release.sh: $*"; exit 1; }
step() { print -r -- "==> $*"; }

detach_dmg() {
  if (( attached )); then
    hdiutil detach -quiet "$mnt" || hdiutil detach -quiet -force "$mnt"
    attached=0
  fi
  [[ -n "$mnt" && -d "$mnt" ]] && rmdir "$mnt" 2>/dev/null
  mnt=""
}
trap detach_dmg EXIT

# Undoes steps 5-6 after a failure: release, remote tag, local tag. Exits 1.
undo() {
  trap - INT TERM HUP
  print -u2 -r -- "release.sh: $*. Dọn dẹp:"
  print -u2 -r -- "  gh release delete $tag --yes"
  gh release delete "$tag" --yes || true
  print -u2 -r -- "  git push --delete origin $tag"
  git push --delete origin "$tag" || true
  print -u2 -r -- "  git tag -d $tag"
  git tag -d "$tag" >/dev/null || true
  tagged=0
  print -u2 -r -- "Đã xoá release và tag $tag. Nhánh $main_branch nếu đã đẩy thì giữ nguyên trên origin. dist/READY được giữ để chạy lại."
  exit 1
}
on_signal() {
  (( tagged )) && undo "bị dừng bởi tín hiệu $1"
  exit $(( 128 + $2 ))
}

json_field() { print -r -- "$1" | plutil -extract "$2" raw -o - - 2>/dev/null; }

# Fails unless tag $tag is absent on origin (git ls-remote exit 2).
check_remote_tag() {
  local r=0
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 || r=$?
  case $r in
    0) die "Tag $tag đã có trên origin. Không đăng lại; tăng phiên bản hoặc xoá tag đó bằng tay." ;;
    2) ;;
    *) die "không đọc được tag trên origin (git ls-remote thoát $r)." ;;
  esac
}

main() {
  local dry=0
  while (( $# )); do
    case "$1" in
      --dry-run) dry=1; shift ;;
      -h|--help) sed -n '2,37p' "$self"; exit 0 ;;
      *) die "tham số không hợp lệ: $1 (xem --help)" ;;
    esac
  done
  cd "$repo" || die "không vào được $repo"

  # Preflight: nothing is created, called or pushed before these pass.
  [[ -f dist/READY ]] || die "Chưa có bản sẵn sàng (không có dist/READY). Chạy sync/sync.sh, hoặc leankeys/build.sh --version X.Y --dmg rồi ghi X.Y vào dist/READY."
  local ver; ver="$(<dist/READY)"; ver="${ver//[[:space:]]/}"
  [[ "$ver" == <->.<-> ]] || die "dist/READY phải chứa phiên bản dạng X.Y, đang là '$ver'."
  tag="v$ver"
  local dmg="dist/LeanKeys-$ver.dmg"
  [[ -f "$dmg" ]] || die "Thiếu $dmg (dist/READY ghi $ver)."
  git rev-parse -q --verify "refs/heads/$main_branch" >/dev/null || die "không có nhánh $main_branch."
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null &&
    die "Tag $tag đã có trong repo. Không đăng lại; tăng phiên bản hoặc xoá tag đó bằng tay."
  local vjson main_ver g_tag v_tag
  vjson="$(git show "refs/heads/${main_branch}:leankeys/LeanKeysKit/Resources/Versions.json" 2>/dev/null)" ||
    die "không đọc được leankeys/LeanKeysKit/Resources/Versions.json trên $main_branch."
  main_ver="$(json_field "$vjson" leankeys)" g_tag="$(json_field "$vjson" gonhanh)" v_tag="$(json_field "$vjson" vikey)"
  [[ "$main_ver" == "$ver" ]] ||
    die "dist/READY ghi $ver nhưng Versions.json trên $main_branch ghi ${main_ver:-?}; DMG không khớp với $main_branch."
  local has_origin=0
  git remote get-url origin >/dev/null 2>&1 && has_origin=1
  (( has_origin )) && check_remote_tag

  # Release notes: engine versions + first-parent log since the previous LeanKeys tag.
  local prev range log
  prev="$(git tag -l 'v*' --merged "refs/heads/$main_branch" --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+$' | head -n 1)"
  if [[ -n "$prev" ]]; then
    range="$prev..refs/heads/$main_branch"
  elif [[ -n "$g_tag" ]] && git rev-parse -q --verify "refs/tags/$g_tag" >/dev/null; then
    range="$g_tag..refs/heads/$main_branch"
  else
    range="refs/heads/$main_branch"
  fi
  log="$(git log --first-parent --format='- %s' -n 40 "$range")"
  local notes="Engine: Gõ Nhanh ${g_tag:-?} · Vikey ${v_tag:-?}

Thay đổi${prev:+ từ $prev}:
${log:-- (không có commit mới)}"

  local push_cmd="git push origin refs/heads/${main_branch}:refs/heads/$main_branch refs/tags/${tag}:refs/tags/$tag"
  print -r -- "Phát hành LeanKeys $ver ($dmg, nhánh $main_branch):"
  print -r -- "  gh auth status"
  print -r -- "  hdiutil attach $dmg (kiểm tra LeanKeys.app), hdiutil detach"
  print -r -- "  in sync/manual-checklist.md, chờ gõ yes"
  (( has_origin )) || print -r -- "  gh repo create $gh_repo --public --source . --remote origin"
  print -r -- "  gh api -X PUT repos/$gh_repo/actions/permissions -F enabled=false"
  print -r -- "  git tag $tag refs/heads/$main_branch"
  print -r -- "  $push_cmd"
  print -r -- "  gh release create $tag $dmg --title \"LeanKeys $ver\" --notes <ghi chú>"
  print -r -- "  rm dist/READY"
  print -r -- ""
  print -r -- "Ghi chú:"
  print -r -- "$notes" | sed 's/^/  /'
  print -r -- ""
  if (( dry )); then
    print -r -- "--dry-run: không gọi gh, không tạo tag, không đẩy gì."
    exit 0
  fi

  # 1. gh
  step "gh auth status"
  gh auth status || die "gh chưa đăng nhập; chạy gh auth login."

  # 2. DMG
  step "hdiutil attach $dmg"
  mnt="$(mktemp -d -t leankeys-release)" || die "mktemp lỗi."
  hdiutil attach -nobrowse -readonly -noverify -mountpoint "$mnt" "$dmg" >/dev/null || die "không mở được $dmg."
  attached=1
  [[ -x "$mnt/LeanKeys.app/Contents/MacOS/LeanKeys" ]] || die "$dmg không chứa LeanKeys.app chạy được."
  detach_dmg
  print -r -- "$dmg có LeanKeys.app."

  # 3. Manual checklist
  print -r -- ""
  cat sync/manual-checklist.md || die "thiếu sync/manual-checklist.md."
  print -r -- ""
  local ans=""
  if [[ "${LEANKEYS_RELEASE_ASSUME_YES:-}" == 1 ]]; then
    print -r -- "LEANKEYS_RELEASE_ASSUME_YES=1: bỏ qua xác nhận."
    ans=yes
  else
    local tty="${LEANKEYS_TTY:-/dev/tty}"
    { : <"$tty" } 2>/dev/null ||
      die "Cần terminal để xác nhận ($tty không đọc được); không nhận yes từ stdin. Chưa tạo tag, chưa đẩy gì."
    print -n -r -- "Đã thử tay xong? Gõ yes để đăng ${tag}: "
    { read -r ans <"$tty" } 2>/dev/null || true
  fi
  [[ "$ans" == yes ]] || die "Đã huỷ (không có xác nhận yes). Chưa tạo tag, chưa đẩy gì."

  # 4. origin, only once confirmed (ruling R27): nothing public exists before the "yes".
  if (( ! has_origin )); then
    if gh repo view "$gh_repo" >/dev/null 2>&1; then
      step "git remote add origin https://github.com/$gh_repo.git"
      git remote add origin "https://github.com/$gh_repo.git" || die "không thêm được remote origin."
    else
      step "gh repo create $gh_repo --public --source . --remote origin"
      gh repo create "$gh_repo" --public --source . --remote origin || die "không tạo được repo $gh_repo."
    fi
    check_remote_tag
  fi
  # Every run, before any push: a half-failed first run may have left origin
  # set with the upstream workflows still enabled.
  step "gh api -X PUT repos/$gh_repo/actions/permissions -F enabled=false"
  gh api -X PUT "repos/$gh_repo/actions/permissions" -F enabled=false >/dev/null ||
    die "không tắt được GitHub Actions trên $gh_repo; tắt trong Settings → Actions rồi chạy lại. Chưa đẩy gì."

  # 5-6. Tag, push, release; undo on failure.
  trap 'on_signal INT 2' INT
  trap 'on_signal TERM 15' TERM
  trap 'on_signal HUP 1' HUP
  step "git tag $tag refs/heads/$main_branch"
  git tag "$tag" "refs/heads/$main_branch" || die "không tạo được tag $tag."
  tagged=1
  step "$push_cmd"
  git push origin "refs/heads/${main_branch}:refs/heads/$main_branch" "refs/tags/${tag}:refs/tags/$tag" ||
    undo "git push lỗi"
  step "gh release create $tag $dmg --title \"LeanKeys $ver\""
  gh release create "$tag" "$dmg" --title "LeanKeys $ver" --notes "$notes" || undo "gh release create lỗi"
  tagged=0
  trap - INT TERM HUP

  # 7.
  rm -f dist/READY
  print -r -- ""
  print -r -- "Đã đăng LeanKeys ${ver}: https://github.com/$gh_repo/releases/tag/$tag"
  exit 0
}

main "$@"
