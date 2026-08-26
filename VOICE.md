# Voice and meeting notes

Two features sharing one pipeline, both entirely on-device.

- **Dictation.** Hold a key, talk, let go, and cleaned-up text is typed into whatever had
  focus.
- **Meeting notes.** Record both sides of a call, transcribe them separately, and
  summarize the result with Apple's on-device model.

Nothing is uploaded. Speech recognition is `SpeechAnalyzer` (macOS 26), cleanup and
summaries are Foundation Models, and both ship with the OS.

---

## Layout

```
Services/Voice/
├── DictationService.swift    the state machine — holds everything below together
├── PushToTalkMonitor.swift   CGEventTap on .flagsChanged, both keys, Escape to cancel
├── AudioPipeline.swift       mic capture, format conversion, level metering
├── SpeechEngine.swift        protocol + AppleSpeechEngine (SpeechAnalyzer)
├── TranscriptCleanup.swift   DictationStyle, rule pass, on-device model pass
├── SelectionRewriter.swift   command mode: rewrite the selection by voice
├── TextInjector.swift        AX insert, pasteboard fallback, secure-field guard
├── Vocabulary.swift          the terms and corrections, as an editable text file
└── DictationHistory.swift    what you dictated, and how fast

Services/Meetings/
├── MeetingRecorder.swift     two captures, two transcribers, one timeline
├── SystemAudioTap.swift      ScreenCaptureKit audio-only capture
├── MeetingSummarizer.swift   map-reduce over the on-device model
├── MeetingStore.swift        Meeting, summary, index, Markdown export
└── CallDetector.swift        notices a call and offers to take notes
```

---

## Decisions worth knowing

**The HUD must never take focus.** `VoiceHUDPanel` is a `.nonactivatingPanel` with
`canBecomeKey == false`. If it took key status, the user's text field would lose focus and
`TextInjector` would have nothing to insert into. Everything else here is replaceable;
this is not. It is also why the HUD cannot be a SwiftUI `Window` scene — a scene is
activatable by construction.

**Push-to-talk needs a `CGEventTap`, not the shortcut system.** Carbon's
`RegisterEventHotKey` — which the rest of Crest's shortcuts use, and which needs no
Accessibility grant — cannot register a bare modifier and never reports a release.
Push-to-talk needs both edges of one key, so it needs a tap, so it needs Accessibility.

**The device-dependent modifier mask is load-bearing.** `CGEventFlags.maskAlternate` is
set whenever *either* Option key is down. Hold Left ⌥, tap Right ⌥, and the release is
invisible: the mic stays open forever. `PushToTalkKey.flag` uses IOKit's `NX_DEVICE*`
masks, which carry the left/right distinction the public constants discard.

**Audio ordering is explicit.** Each capture yields into an `AsyncStream` drained by a
single task. A `Task` per buffer would be simpler and would silently scramble the
transcript — unstructured tasks have no ordering guarantee.

**Buffers are copied, never borrowed.** `AVAudioEngine` recycles the buffer it hands a tap
the instant the callback returns, and ScreenCaptureKit does the same with its
`CMSampleBuffer`. `AudioChunk`'s `@unchecked Sendable` is only sound because every
producer allocates fresh storage first.

**Two captures, not one plus diarization.** The microphone is you; the system output is
everyone else. Running a separate speech session on each gives correct speaker
attribution for free. One mixed recording plus a diarization model would mean another
download, more latency, and a guess.

**Summarizing is map-reduce because it has to be.** The on-device model's context window
covers a couple of minutes of talking, not an hour. Feeding a whole meeting in one prompt
does not give a worse summary, it throws `exceededContextWindowSize` and gives none. The
transcript is cut into 2400-character slices, each reduced to structured notes, and the
notes merged — folded again in rounds if they are still too long. Every call gets a fresh
`LanguageModelSession`, because a session's own transcript counts against the same window.

**The cleanup pass is guarded.** Dictate "what is the capital of france" and a helpful
model returns "The capital of France is Paris." — which would then be typed into your
document. `ModelCleanup.isPlausibleCleanup` rejects output that introduces a content word
that was never spoken. Every rejection falls back to the rule pass, so an utterance is
never lost.

**Only committed text becomes a transcript segment.** Engines revise what they think they
heard. The meeting recorder diffs `TranscriptionChunk.committedText`, which only ever
grows; diffing the displayed text would write half-heard words into the transcript and
leave them there.

---

## Permissions

| Grant | Needed for | Asked how |
|---|---|---|
| Accessibility | The event tap that sees the held key, and the AX text insert | System Settings only — there is no programmatic request |
| Microphone | Hearing you | Prompted on first use |
| Screen & System Audio Recording | Hearing the other side of a call | System Settings |

macOS ties every grant to the code signature, so a rebuilt binary may have to be granted
again. Crest polls for the Accessibility grant while it is missing and arms the tap
the moment it appears, so no relaunch is needed.

Without the screen-recording grant a meeting still records — your side only — and says so
rather than producing half a conversation with no explanation.

---

## Testing

```bash
./Tests/run.sh
```

Compiles the real cleanup, vocabulary, slicing and export sources into a small executable
and checks them. Not an XCTest bundle: the app target has no test host, and everything
worth checking here is a free function over values.

What that cannot cover is anything needing a microphone, a call, or a granted event tap.
Those need a person to hold the key and talk.
