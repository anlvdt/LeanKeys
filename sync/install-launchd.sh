#!/bin/zsh
# Usage: sync/install-launchd.sh [--check | --uninstall]
#
# Installs the daily sync job (sync/com.leankeys.sync.plist, 03:00) as a user
# LaunchAgent: replaces <repo> with this repository's path, checks the result
# with plutil -lint, copies it to ~/Library/LaunchAgents/ and bootstraps it
# into gui/<uid>.
#   --check      only render into a temp file and lint it; prints the result
#                and touches neither ~/Library nor launchctl
#   --uninstall  boot the job out and remove the installed plist

emulate -L zsh
setopt no_unset pipe_fail err_return

label=com.leankeys.sync
repo="${0:A:h:h}"
template="$repo/sync/com.leankeys.sync.plist"
target="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

mode=install
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  --uninstall) mode=uninstall ;;
  -h|--help) sed -n '2,11p' "${0:A}"; exit 0 ;;
  *) print -u2 "install-launchd.sh: unknown argument: $1"; exit 2 ;;
esac

if [[ $mode == uninstall ]]; then
  launchctl bootout "$domain/$label" 2>/dev/null || true
  rm -f "$target"
  print -r -- "Removed $label ($target)."
  exit 0
fi

# The path goes inside a double-quoted zsh -lc string.
if [[ "$repo" == *[\"\$\`\\]* ]]; then
  print -u2 "install-launchd.sh: repo path contains \", \$, \` or \\: $repo"
  exit 1
fi

# Render the template with the repo path, XML-escaped.
render() {
  local esc="$repo"
  esc="${esc//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
  local text; text="$(<"$template")"
  print -r -- "${text//&lt;repo&gt;/$esc}" > "$1"
}

tmp="$(mktemp -t leankeys-sync-plist)"
trap 'rm -f "$tmp"' EXIT
render "$tmp"
plutil -lint "$tmp" >/dev/null || { plutil -lint "$tmp"; print -u2 "rendered plist is invalid"; exit 1; }

if [[ $mode == check ]]; then
  print -r -- "$(plutil -lint "$tmp")"
  cat "$tmp"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$repo/sync/reports"
cp "$tmp" "$target"
launchctl bootout "$domain/$label" 2>/dev/null || true
launchctl bootstrap "$domain" "$target"
print -r -- "Installed $label → $target (daily 03:00). Run now: launchctl kickstart $domain/$label"
