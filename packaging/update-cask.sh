#!/usr/bin/env bash
# Points the cask at a new release: ./packaging/update-cask.sh 1.0.1 <sha256>
set -euo pipefail

VERSION="${1:?usage: $0 <version> <sha256>}"
SHA="${2:?usage: $0 <version> <sha256>}"
CASK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/homebrew-tap/Casks/diskpilot.rb"

/usr/bin/sed -i '' \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$CASK"

grep -E "^  (version|sha256)" "$CASK"
echo "Now commit and push the tap repo."
