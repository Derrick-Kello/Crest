#!/usr/bin/env bash
#
# Builds a downloadable Crest.dmg without notarising it.
#
#   ./packaging/release-unnotarized.sh 1.0.0
#
# This is the interim path, and it is deliberately a separate script rather than a
# flag on release.sh. The two produce genuinely different artefacts and mixing them
# invites shipping the wrong one: release.sh makes a disk image Apple has checked
# and Gatekeeper opens silently, this one makes a disk image every user has to
# override by hand. When the Developer ID certificate exists, use release.sh and
# delete this.
#
# What users get:
#   macOS refuses the app on first open — "Apple could not verify Crest is free of
#   malware" — because an Apple Development certificate cannot be notarised. It
#   only authorises the app on Macs registered to the signing team. Users have to
#   either strip the quarantine attribute or press Open Anyway in System Settings.
#   The website's install section and FAQ already say so.
#
# -exportArchive is not used here. ExportOptions.plist declares the developer-id
# method, which requires a certificate this path does not have, so the app is taken
# straight from a Release build instead.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>   e.g. $0 1.0.0" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="$(grep -E '^TEAM_ID=' "$ROOT/packaging/release.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d ' \r')"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# Any valid certificate for our team. Selected by hash because a name can match
# several certificates and codesign refuses an ambiguous identity.
step "Choosing a signing identity"
SIGN_ID=""
while IFS= read -r line; do
  [[ "$line" == *CSSMERR* ]] && continue
  hash="$(awk '{print $2}' <<<"$line")"
  ou="$(security find-certificate -a -Z -p login.keychain-db 2>/dev/null \
        | awk -v h="$hash" '/^SHA-1 hash:/ {f=($3==h)} /BEGIN CERT/,/END CERT/ {if (f) print}' \
        | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU=([^,]+).*/\1/p')"
  if [[ -z "$TEAM_ID" || "$ou" == "$TEAM_ID" ]]; then SIGN_ID="$hash"; break; fi
done < <(security find-identity -v -p codesigning 2>/dev/null | grep -E '^ +[0-9]+\)')

if [[ -z "$SIGN_ID" ]]; then
  echo "No usable signing certificate for team ${TEAM_ID:-<unset>}." >&2
  exit 1
fi
security find-identity -v -p codesigning | grep "$SIGN_ID" | sed -E 's/.*"(.*)".*/    \1/'

if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo
  echo "    A Developer ID certificate exists. Use release.sh instead — it notarises." >&2
  exit 1
fi

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
STAGE="$BUILD/stage"
DMG="$ROOT/Crest.dmg"
mkdir -p "$STAGE"

step "Building $VERSION"
xcodebuild -project "$ROOT/Crest.xcodeproj" -scheme Crest -configuration Release \
  -derivedDataPath "$BUILD/dd" \
  MARKETING_VERSION="$VERSION" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  ONLY_ACTIVE_ARCH=NO \
  build >"$BUILD/log" 2>&1 || { tail -40 "$BUILD/log"; exit 1; }

APP="$BUILD/dd/Build/Products/Release/Crest.app"
[[ -d "$APP" ]] || { echo "build produced no app" >&2; exit 1; }

step "Checking what came out"
lipo -archs "$APP/Contents/MacOS/Crest"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Identifier|Authority=Apple|TeamIdentifier"
codesign --verify --strict "$APP" && echo "    signature valid"

step "Building the disk image"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Crest" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$SIGN_ID" "$DMG"

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

step "Done"
cat <<SUMMARY
Disk image : $DMG
sha256     : $SHA

NOT notarised. Users will see "Apple could not verify Crest is free of malware"
on first open and must run the xattr line the website gives them.

Next:
  gh release create v$VERSION "$DMG" --title "Crest $VERSION" --notes "..."
  ./packaging/update-cask.sh $VERSION $SHA
SUMMARY
