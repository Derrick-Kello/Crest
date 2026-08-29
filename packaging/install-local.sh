#!/usr/bin/env bash
#
# Builds Crest and installs it to /Applications, then clears the stale
# Accessibility grant so the new binary can ask for its own.
#
#   ./packaging/install-local.sh
#   ./packaging/install-local.sh --new-identity   # once, see below
#   ./packaging/install-local.sh --check          # show the identity, build nothing
#
# Why this exists
# ---------------
# macOS shows one row per application in Privacy & Security ▸ Accessibility, but
# it grants the permission to one specific *binary*, identified by its code
# signature. Crest has no developer certificate, so every build is signed ad hoc,
# and an ad-hoc signature has nothing durable for the system to anchor a grant to
# except the hash of the binary itself — which changes on every single compile.
#
# The result is a switch that reads as on while the API keeps refusing, and no
# permission prompt, because the system already has a record for the bundle id and
# considers the question answered. Toggling the switch does not fix it. Removing
# the record and asking again does.
#
# --new-identity creates a self-signed code-signing certificate in your login
# keychain and makes it the signing identity. That gives the system a stable thing
# to anchor the grant to, so the permission survives rebuilds and you stop having
# to re-grant it. Run it once. It will prompt for your keychain password, and it
# adds a certificate you can remove in Keychain Access at any time.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.smarthive.Crest"
TARGET="/Applications/Crest.app"
IDENTITY_NAME="Crest Local Signing"

# ---------------------------------------------------------------- identity

create_identity() {
  if security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1; then
    echo "==> '$IDENTITY_NAME' already exists in the login keychain"
    return
  fi

  echo "==> Creating a self-signed code-signing certificate"
  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN

  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$work/key.pem" -out "$work/cert.pem" \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

  openssl pkcs12 -export -out "$work/bundle.p12" \
    -inkey "$work/key.pem" -in "$work/cert.pem" -passout pass: 2>/dev/null

  # -T /usr/bin/codesign lets codesign use the key without a prompt per build.
  security import "$work/bundle.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "" -T /usr/bin/codesign -A >/dev/null

  # Trusting it for code signing only. This prompts for your keychain password.
  echo "==> Trusting the certificate for code signing (expect a password prompt)"
  security add-trusted-cert -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$work/cert.pem"

  echo "==> Done. Rebuilds will now keep their Accessibility permission."
}

if [[ "${1:-}" == "--new-identity" ]]; then
  create_identity
fi

# Pick the best identity available, in descending order of durability. Any real
# certificate beats the self-signed one, and the self-signed one beats ad hoc,
# because all that matters for keeping the Accessibility grant is that the thing
# TCC anchors to stays the same between builds.
#
# Developer ID is listed first only because a machine that has one is set up to
# ship; for the permission problem an Apple Development certificate does the same
# job. Ad hoc is the only option that cannot work, and it is kept as a fallback so
# the script still builds on a machine with no certificates at all.
# The team Crest signs for, so a certificate belonging to a different team is not
# picked by accident. Read from release.env when it is there.
TEAM_ID="${TEAM_ID:-}"
if [[ -z "$TEAM_ID" && -f "$ROOT/packaging/release.env" ]]; then
  TEAM_ID="$(grep -E '^TEAM_ID=' "$ROOT/packaging/release.env" | tail -1 | cut -d= -f2- | tr -d ' \r')"
fi

# The team a certificate belongs to lives in the subject's OU field, not in its
# name. Two teams can both hold a certificate called "Apple Development: Your
# Name", so the name alone cannot tell them apart.
cert_team() {
  security find-certificate -a -Z -p login.keychain-db 2>/dev/null \
    | awk -v h="$1" '/^SHA-1 hash:/ {found=($3==h)} /BEGIN CERT/,/END CERT/ {if (found) print}' \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU=([^,]+).*/\1/p'
}

# Returns a SHA-1 hash rather than a name, because a name is not unique. Asking
# codesign for "Apple Development" on a machine holding four such certificates
# fails outright with an ambiguity error, and picking the wrong one of them signs
# for the wrong team or with a revoked certificate. A hash names exactly one.
pick_identity() {
  local line hash name team

  for prefix in "Developer ID Application" "Apple Development" "$IDENTITY_NAME"; do
    while IFS= read -r line; do
      # A revoked or expired certificate is still listed, with the reason in
      # parentheses. Signing with one produces a build macOS refuses to trust.
      [[ "$line" == *CSSMERR* ]] && continue

      hash="$(awk '{print $2}' <<<"$line")"
      name="$(sed -E 's/.*"(.*)".*/\1/' <<<"$line")"
      [[ "$name" == "$prefix"* ]] || continue

      # The self-signed fallback has no Apple team and is exempt from the check.
      if [[ -n "$TEAM_ID" && "$prefix" != "$IDENTITY_NAME" ]]; then
        team="$(cert_team "$hash")"
        [[ "$team" == "$TEAM_ID" ]] || continue
      fi

      printf '%s' "$hash"
      return
    done < <(security find-identity -v -p codesigning 2>/dev/null | grep -E '^ +[0-9]+\)')
  done
  printf '%s' "-"
}

SIGN_ID="$(pick_identity)"

if [[ "$SIGN_ID" == "-" ]]; then
  echo "==> No signing identity found, signing ad hoc"
  echo "    The Accessibility grant will not survive the next rebuild."
  echo "    Run '$0 --new-identity' once to fix that permanently,"
  echo "    or create an Apple Development certificate in Xcode."
else
  echo "==> Signing with $(security find-identity -v -p codesigning | grep "$SIGN_ID" | sed -E 's/.*"(.*)".*/\1/')"
  echo "    hash $SIGN_ID, team ${TEAM_ID:-unset}"
fi

# Stops here when asked, so the identity choice can be checked without building
# or touching /Applications.
if [[ "${1:-}" == "--check" ]]; then
  exit 0
fi

# ---------------------------------------------------------------- build

echo "==> Building Release"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

xcodebuild -project "$ROOT/Crest.xcodeproj" -scheme Crest -configuration Release \
  -derivedDataPath "$BUILD/dd" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  build >"$BUILD/log" 2>&1 || { tail -40 "$BUILD/log"; exit 1; }

APP="$BUILD/dd/Build/Products/Release/Crest.app"
[[ -d "$APP" ]] || { echo "build produced no app" >&2; exit 1; }

# ---------------------------------------------------------------- install

echo "==> Quitting any running copy"
osascript -e 'tell application "Crest" to quit' 2>/dev/null || true
killall Crest 2>/dev/null || true
sleep 1

if [[ -d "$TARGET" ]]; then
  echo "==> Replacing $TARGET"
  rm -rf "$TARGET"
fi
cp -R "$APP" "$TARGET"

echo "==> Installed:"
codesign -dv --verbose=2 "$TARGET" 2>&1 | grep -E "Identifier|Signature|Authority" || true

# ---------------------------------------------------------------- permission

# Clearing every Accessibility record for the bundle id. This is deliberately
# unconditional: the stale entry is invisible from here (reading TCC.db needs Full
# Disk Access) and leaving it in place is what causes the silent refusal.
echo "==> Clearing the old Accessibility record"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

open "$TARGET"

cat <<'DONE'

==> Installed and launched.

    Crest will ask for Accessibility. Grant it, then open the menu bar item
    and turn on Tiling, or press ⌥⇧T.

    If no prompt appears, open:
      System Settings ▸ Privacy & Security ▸ Accessibility
    and switch Crest on there.
DONE
