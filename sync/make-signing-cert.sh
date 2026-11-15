#!/bin/zsh
# Creates the "LeanKeys Self-Signed" code-signing identity in the login keychain. Run once, interactively:
#   zsh sync/make-signing-cert.sh
# build.sh signs with this identity when it is present, so the Accessibility grant survives updates.
# The .p12 backup and its password are yours to keep: losing them means you cannot restore the identity on another Mac.
# Never prints or stores a password. security(1) has no stdin option, so the two `security` calls below take the
# password as an argument; that is why they are the only places a password appears on a command line.

emulate -L zsh
setopt errexit no_unset pipe_fail
umask 077   # the .p12 backup and temp files are readable by this user only

CN="LeanKeys Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
openssl_bin=/usr/bin/openssl

fail() { print -r -- "make-signing-cert.sh: $*" >&2; exit 1; }

# 1. Refuse to overwrite an existing identity.
existing="$(security find-identity -p codesigning 2>/dev/null || true)"
if [[ "$existing" == *"\"$CN\""* ]]; then
  print -r -- "The identity \"$CN\" already exists. To replace it, remove it first:"
  print -r -- "  security delete-identity -c \"$CN\" \"$KEYCHAIN\""
  print -r -- "then run this script again."
  print -r -- "To retry only the key partition step (type your login keychain password in place of the placeholder):"
  print -r -- "  security set-key-partition-list -S apple-tool:,apple: -s -k '<login keychain password>' \"$KEYCHAIN\""
  exit 1
fi

# 2. Generate the key and self-signed certificate in a private temp dir, removed on exit.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
print -r -- "==> Generating key and certificate (20 years)"
$openssl_bin req -x509 -newkey rsa:2048 -days 7300 -nodes \
  -subj "/CN=$CN" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem"

# 3. Ask for the backup path and a password, typed twice.
print -n -- "Backup path for the .p12 file (e.g. ~/Desktop/leankeys-signing.p12): "
read -r backup
backup="${backup/#\~/$HOME}"
[[ -n "$backup" ]] || fail "no backup path given"
[[ ! -e "$backup" ]] || fail "$backup already exists; choose another path"

print -n -- "Backup password: "
read -rs pw1; print
print -n -- "Repeat backup password: "
read -rs pw2; print
[[ -n "$pw1" && "$pw1" == "$pw2" ]] || fail "passwords are empty or do not match"
pw="$pw1"
unset pw1 pw2

# 4. Export the key and certificate as .p12. The password goes through an environment variable, never argv.
print -r -- "==> Exporting backup"
if ! LK_P12_PASS="$pw" $openssl_bin pkcs12 -export -legacy \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$CN" \
    -out "$backup" -passout env:LK_P12_PASS 2>/dev/null; then
  LK_P12_PASS="$pw" $openssl_bin pkcs12 -export \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$CN" \
    -out "$backup" -passout env:LK_P12_PASS
fi
chmod 600 "$backup"

# 5. Import into the login keychain. security(1) has no stdin option, so -P takes the password from a variable.
print -r -- "==> Importing into the login keychain"
security import "$backup" -k "$KEYCHAIN" -P "$pw" -T /usr/bin/codesign

# 6. Let codesign and Apple tools use the key without a prompt (needed by the 03:00 sync job).
print -n -- "Login keychain password (to allow codesign without prompts): "
read -rs login_pw; print
rc=0
security set-key-partition-list -S apple-tool:,apple: -s -k "$login_pw" "$KEYCHAIN" >/dev/null || rc=$?
unset login_pw pw
if (( rc )); then
  print -u2 -r -- "The identity is imported, but the key partition list was not set (exit $rc): codesign may prompt, and the 03:00 sync job would fail."
  print -u2 -r -- "Retry only this step, with your login keychain password in place of the placeholder:"
  print -u2 -r -- "  security set-key-partition-list -S apple-tool:,apple: -s -k '<login keychain password>' \"$KEYCHAIN\""
  exit 1
fi

# 7. Show the result.
print -r -- "==> Done. Identity:"
security find-identity -p codesigning | grep -F "\"$CN\"" || fail "identity not found after import"
print -r -- ""
print -r -- "Keep the .p12 file and its password safe. Store them outside this Mac, for example in a password manager."
