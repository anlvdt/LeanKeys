#!/bin/zsh
# Usage: sync/check-divergence.sh <gonhanh-tag>
#
# Checks that every edit to a file that exists at <gonhanh-tag> is a
# registered LeanKeys hook. Exits 0 when clean; exits 1 and prints
# file:line for each violation; exits 2 on bad usage.
#
# A changed (+) line is allowed when it carries "LEANKEYS-HOOK: <name>", or
# when it sits in a contiguous block of added lines that opens with
# "LEANKEYS-HOOK-BEGIN: <name>" and closes with "LEANKEYS-HOOK-END".
# Removed (-) lines are allowed when they carry a marker, or when their hunk
# also adds lines (a replacement, judged by those added lines). A hunk that
# only removes upstream lines is a violation.
# Every hook name must be registered for that file in sync/hooks.txt as
# "<name>\t<path>". "FILE\t<path>" allows replacing the whole file.

emulate -L zsh
setopt no_unset pipe_fail

if (( $# != 1 )); then
  print -u2 "usage: $0 <gonhanh-tag>"
  exit 2
fi
tag="$1"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { print -u2 "not inside a git repository"; exit 2; }
cd "$root" || exit 2

if ! git rev-parse --quiet --verify "$tag^{commit}" >/dev/null; then
  print -u2 "unknown tag: $tag"
  exit 2
fi

hooks="sync/hooks.txt"
[[ -f "$hooks" ]] || hooks=/dev/null

excludes=(
  ':!vendor' ':!leankeys' ':!sync' ':!tests/sync' ':!docs/superpowers'
  ':!Package.swift' ':!.github/README.md' ':!ACKNOWLEDGEMENTS.md'
  ':!.githooks' ':!.gitmodules'
)
diff_opts=(--no-color --no-ext-diff --no-textconv --no-renames --diff-filter=M)

files=("${(@f)$(git -c core.quotePath=false diff --name-only "${diff_opts[@]}" "$tag" -- . "${excludes[@]}")}")

result=0
tab=$'\t'
for file in "${files[@]}"; do
  [[ -n "$file" ]] || continue
  if grep -qxF -- "FILE${tab}${file}" "$hooks"; then
    continue
  fi
  git -c core.quotePath=false diff -U0 "${diff_opts[@]}" "$tag" -- "$file" |
    awk -v file="$file" -v hooks="$hooks" '
      BEGIN {
        while ((getline line < hooks) > 0) {
          if (line ~ /^#/) continue
          n = split(line, f, "\t")
          if (n >= 2) registered[f[1] SUBSEP f[2]] = 1
        }
        bad = 0; inhunk = 0; nplus = 0; nminus = 0
      }
      function violation(ln, msg) { print file ":" ln ": " msg; bad = 1 }
      # Hook name after a marker prefix, or "" if the line has none.
      function hook_name(s, prefix) {
        if (!match(s, prefix "[A-Za-z0-9_.-]+")) return ""
        return substr(s, RSTART + length(prefix), RLENGTH - length(prefix))
      }
      function flush(   i, j, name) {
        for (i = 1; i <= nplus; i++) ok[i] = 0
        for (i = 1; i <= nplus; i++) {
          name = hook_name(P[i], "LEANKEYS-HOOK: ")
          if (name == "") name = hook_name(P[i], "LEANKEYS-HOOK-BEGIN: ")
          if (name != "" && !((name SUBSEP file) in registered))
            violation(PL[i], "hook \"" name "\" is not registered for " file " in sync/hooks.txt")
          if (hook_name(P[i], "LEANKEYS-HOOK: ") != "") ok[i] = 1
        }
        for (i = 1; i <= nplus; i++) {
          if (hook_name(P[i], "LEANKEYS-HOOK-BEGIN: ") == "") continue
          for (j = i + 1; j <= nplus; j++) if (P[j] ~ /LEANKEYS-HOOK-END/) break
          if (j > nplus) continue
          for (; i <= j; i++) ok[i] = 1
          i = j
        }
        for (i = 1; i <= nplus; i++)
          if (!ok[i]) violation(PL[i], P[i])
        if (nplus == 0)
          for (i = 1; i <= nminus; i++)
            if (M[i] !~ /LEANKEYS-HOOK/) violation(start, "(removed) " M[i])
        nplus = 0; nminus = 0
      }
      /^Binary files / { violation(0, "binary file changed"); next }
      /^@@ / {
        if (inhunk) flush()
        inhunk = 1
        match($0, /\+[0-9]+/)
        start = substr($0, RSTART + 1, RLENGTH - 1) + 0
        ln = start
        next
      }
      !inhunk { next }
      /^\+/ { nplus++; P[nplus] = substr($0, 2); PL[nplus] = ln++; next }
      /^-/  { nminus++; M[nminus] = substr($0, 2); next }
      END { if (inhunk) flush(); exit bad }
    ' || result=1
done

exit $result
