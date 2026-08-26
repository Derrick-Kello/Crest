#!/bin/bash
# Runs the pure-logic checks over the real voice and meeting sources.
#
# Not an XCTest bundle on purpose: the app target has no test host, and everything
# worth checking here — the cleanup guard, the vocabulary rewriter, transcript
# slicing, Markdown export — is a free function over values. Compiling the real
# files into a small executable tests the shipping code rather than a copy of it.
#
#   ./Tests/run.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -O -o "$out/voicetests" \
  "$root/Tests/VoiceLogic/main.swift" \
  "$root/Crest/Services/Voice/AudioPipeline.swift" \
  "$root/Crest/Services/Voice/TranscriptCleanup.swift" \
  "$root/Crest/Services/Voice/Vocabulary.swift" \
  "$root/Crest/Services/Voice/DictationHistory.swift" \
  "$root/Crest/Services/Voice/DictationAnalytics.swift" \
  "$root/Crest/Services/Meetings/MeetingAnalytics.swift" \
  "$root/Crest/Services/Meetings/MeetingStore.swift" \
  "$root/Crest/Services/Meetings/MeetingSummarizer.swift"

"$out/voicetests"
