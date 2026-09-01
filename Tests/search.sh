#!/bin/bash
# Runs the search ranking checks over the real source.
#
# Same shape as tiling.sh, and for the same reason: `FileRanking` is a pure
# function from a path and a query to a number, with no Spotlight and no disk
# involved, so it can be compiled into a small executable and checked without a
# populated metadata index. The rules are where the bugs that are hard to see
# live — a search that quietly drops folders looks exactly like a search that
# works.
#
#   ./Tests/search.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -O -o "$out/searchtests" \
  "$root/Tests/SearchLogic/main.swift" \
  "$root/Crest/Services/FileRanking.swift"

"$out/searchtests"
