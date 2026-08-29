#!/bin/bash
# Runs the layout checks over the real tiling source.
#
# Same shape as run.sh, and for the same reason: `TilingLayout` is a pure function
# from a window count to a set of rectangles, with no Accessibility and no windows
# involved, so it can be compiled into a small executable and checked without a
# Mac full of open apps. The arithmetic is where the bugs that are hard to see
# live — a pane one gap too wide looks fine until two of them overlap.
#
#   ./Tests/tiling.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -O -o "$out/tilingtests" \
  "$root/Tests/TilingLayout/main.swift" \
  "$root/Crest/Services/Tiling/TilingLayout.swift"

"$out/tilingtests"
