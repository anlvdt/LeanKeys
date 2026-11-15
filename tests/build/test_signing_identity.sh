#!/bin/zsh
# Unit checks for pick_signing_kind in leankeys/build.sh. Sources build.sh in source-only mode: no build, no keychain changes.
# Run: zsh tests/build/test_signing_identity.sh

emulate -L zsh
setopt no_unset pipe_fail

root="${0:A:h:h:h}"
build="$root/leankeys/build.sh"
self_signed_line='  1) ABCDEF "LeanKeys Self-Signed" (CSSMERR_TP_NOT_TRUSTED)'

passed=0
failed=0
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    passed=$((passed + 1)); print -r -- "ok   $1"
  else
    failed=$((failed + 1)); print -r -- "FAIL $1: expected '$2', got '$3'"
  fi
}

# pick <identities-text> [VAR=value ...]: prints pick_signing_kind's answer, run in a fresh shell.
pick() {
  local ids="$1"; shift
  # Without the source-only guard, sourcing build.sh would start a full build, so refuse to source it.
  grep -q 'LEANKEYS_SOURCE_ONLY' "$build" || return 0
  env -u LEANKEYS_SIGN_IDENTITY -u LEANKEYS_NOTARY_PROFILE "$@" \
    LEANKEYS_SOURCE_ONLY=1 BUILD_SH="$build" IDS="$ids" \
    zsh -c 'set --; source "$BUILD_SH"; pick_signing_kind "$IDS"' 2>/dev/null
}

check "empty identities give adhoc" adhoc "$(pick '')"
check "other identity only gives adhoc" adhoc "$(pick '  1) ABCDEF "Apple Development: someone" (CSSMERR_TP_NOT_TRUSTED)')"
check "self-signed identity gives self-signed" self-signed "$(pick "$self_signed_line")"
check "both env vars give developer-id" developer-id \
  "$(pick "$self_signed_line" LEANKEYS_SIGN_IDENTITY="Developer ID Application: Test" LEANKEYS_NOTARY_PROFILE=test-profile)"
check "sign identity without notary profile gives self-signed" self-signed \
  "$(pick "$self_signed_line" LEANKEYS_SIGN_IDENTITY="Developer ID Application: Test")"

# require <kind> [VAR=value ...]: prints require_stable_signing's stderr and exit status, run in a fresh shell.
require() {
  local kind="$1"; shift
  env -u LEANKEYS_REQUIRE_STABLE_SIGNING "$@" LEANKEYS_SOURCE_ONLY=1 BUILD_SH="$build" KIND="$kind" \
    zsh -c 'set --; source "$BUILD_SH"; require_stable_signing "$KIND"' 2>&1
  print -r -- "status=$?"
}
missing_msg='Stable signing required (LEANKEYS_REQUIRE_STABLE_SIGNING=1) but "LeanKeys Self-Signed" was not found — unlock the login keychain or run sync/make-signing-cert.sh'

check "required and adhoc fails with the message" "$missing_msg
status=1" "$(require adhoc LEANKEYS_REQUIRE_STABLE_SIGNING=1)"
check "required and self-signed passes" "status=0" "$(require self-signed LEANKEYS_REQUIRE_STABLE_SIGNING=1)"
check "required and developer-id passes" "status=0" "$(require developer-id LEANKEYS_REQUIRE_STABLE_SIGNING=1)"
check "not required and adhoc passes" "status=0" "$(require adhoc)"
check "required=0 and adhoc passes" "status=0" "$(require adhoc LEANKEYS_REQUIRE_STABLE_SIGNING=0)"

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
