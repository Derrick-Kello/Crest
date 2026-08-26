#!/usr/bin/env bash
#
# Builds, signs, notarises and staples a Crest release, then prints the
# values the Homebrew cask needs.
#
#   TEAM_ID=XXXXXXXXXX ./packaging/release.sh 1.0.0
#
# Requires, once per machine:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. A stored notarytool profile:
#        xcrun notarytool store-credentials crest-notary \
#          --apple-id you@example.com --team-id XXXXXXXXXX
#      It asks for an app-specific password from appleid.apple.com.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>   e.g. $0 1.0.0" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Settings live in packaging/release.env, which is gitignored. Anything already
# in the environment wins, so one-off overrides still work.
CONFIG="$ROOT/packaging/release.env"
if [[ -f "$CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG"
fi

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "TEAM_ID is not set." >&2
  echo "Copy packaging/release.env.example to packaging/release.env and fill it in." >&2
  exit 78
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-crest-notary}"
IDENTITY="${IDENTITY:-Developer ID Application}"
BUILD="$ROOT/.release"
ARCHIVE="$BUILD/Crest.xcarchive"
EXPORT_DIR="$BUILD/export"
STAGE="$BUILD/stage"
DMG="$BUILD/Crest.dmg"
APP="$EXPORT_DIR/Crest.app"
PLIST="$BUILD/ExportOptions.plist"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Checking for a signing identity"
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "No '$IDENTITY' certificate in the keychain." >&2
  echo "Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application" >&2
  exit 1
fi

rm -rf "$BUILD"
mkdir -p "$BUILD" "$STAGE"

# The checked-in plist carries a placeholder team id so it is safe to commit.
sed "s/REPLACE_WITH_TEAM_ID/$TEAM_ID/" "$ROOT/packaging/ExportOptions.plist" > "$PLIST"

step "Archiving $VERSION"
xcodebuild archive \
  -project "$ROOT/Crest.xcodeproj" \
  -scheme Crest \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  ONLY_ACTIVE_ARCH=NO \
  | grep -E "^(\*\*|error|warning: unable)" || true

step "Exporting"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PLIST"

step "Checking what came out"
lipo -archs "$APP/Contents/MacOS/Crest"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Signature|TeamIdentifier|flags"
codesign --verify --deep --strict --verbose=2 "$APP"

step "Building the disk image"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Crest" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

step "Notarising, this waits for Apple"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

step "Stapling and verifying"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

step "Done"
cat <<SUMMARY
Disk image : $DMG
sha256     : $SHA

Next:
  gh release create v$VERSION "$DMG" --title "Crest $VERSION" --notes "..."
  ./packaging/update-cask.sh $VERSION $SHA
SUMMARY
