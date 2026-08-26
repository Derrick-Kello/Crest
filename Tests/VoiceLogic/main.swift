import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok   \(label)" : "  FAIL \(label)")
    if !condition { failures += 1 }
}

print("cleanup guard")
check("rejects an answered question",
      !ModelCleanup.isPlausibleCleanup(
        original: "what is the capital of france",
        cleaned: "The capital of France is Paris."))
check("accepts an ordinary tidy",
      ModelCleanup.isPlausibleCleanup(
        original: "um so we should uh ship the beta on friday you know",
        cleaned: "So we should ship the beta on Friday."))
check("rejects a narrating model",
      !ModelCleanup.isPlausibleCleanup(
        original: "ship the beta on friday",
        cleaned: "Here's the cleaned transcript: Ship the beta on Friday."))
check("rejects an empty result",
      !ModelCleanup.isPlausibleCleanup(original: "ship it", cleaned: ""))

print("rule-based cleanup by style")
let rules = RuleBasedCleanup()
let sem = DispatchSemaphore(value: 0)
Task {
    defer { sem.signal() }
    let raw = "um so we should ship the beta on friday"
    check("prose starts a sentence and ends it",
          await rules.clean(raw, style: .prose) == "So we should ship the beta on friday.")
    check("chat adds no trailing full stop",
          await rules.clean(raw, style: .chat) == "So we should ship the beta on friday")
    check("verbatim changes nothing", await rules.clean(raw, style: .verbatim) == raw)

    check("code builds an absolute path",
          await rules.clean("cd um slash users slash mac", style: .code) == "cd /users/mac")
    check("code builds a flag",
          await rules.clean("run the build double dash verbose", style: .code) == "run the build --verbose")
    check("code keeps a token-initial symbol spaced",
          await rules.clean("export dollar sign home", style: .code) == "export $home")
    check("code glues a filename together",
          await rules.clean("open build underscore output dot json", style: .code) == "open build_output.json")
    check("code neither capitalizes nor punctuates",
          await rules.clean("run the tests", style: .code) == "run the tests")
}
sem.wait()

print("vocabulary corrector")
let corrector = VocabularyCorrector(entries: [
    .correction(hear: "type script", write: "TypeScript"),
    .correction(hear: "cloud code", write: "Claude Code"),
    .correction(hear: "cloud", write: "Claude"),
])
check("rewrites a spaced phrase", corrector.apply(to: "open type script").text == "open TypeScript")
check("rewrites a glued phrase", corrector.apply(to: "open typescript").text == "open TypeScript")
check("rewrites a hyphenated phrase", corrector.apply(to: "open type-script").text == "open TypeScript")
check("longest rule wins", corrector.apply(to: "run cloud code now").text == "run Claude Code now")
check("does not bite into a longer word", corrector.apply(to: "check cloudflare").text == "check cloudflare")
check("reports what fired", corrector.apply(to: "open type script").applied.count == 1)

print("vocabulary file round trip")
let parsed = VocabularyStore.parse("""
# a comment
Anthropic
type script -> TypeScript
# off: whisper flow -> Wispr Flow
""")
check("parses three entries", parsed.count == 3)
check("first is a term", parsed[0].kind == .term && parsed[0].write == "Anthropic")
check("second is a correction", parsed[1].kind == .correction && parsed[1].hear == "type script")
check("third is disabled", !parsed[2].isEnabled)
check("a disabled entry round trips", parsed[2].fileLine == "# off: whisper flow -> Wispr Flow")

print("bias list")
let biased = VocabularyCorrector.biasPhrases(from: [
    VocabularyEntry(kind: .term, write: "Automatic", isAutomatic: true),
    .term("Mine"),
])
check("user entries come first", biased.first == "Mine")
check("the list is capped", VocabularyCorrector.biasPhrases(
    from: (0..<200).map { .term("Term\($0)") }).count == VocabularyCorrector.biasLimit)

print("summary slicing")
var long = ""
for index in 0..<400 { long += "You: line number \(index) with some words in it\n" }
let slices = MeetingSummarizer.slice(long)
check("every slice fits the window", slices.allSatisfy { $0.count <= 2400 })
check("nothing is lost", slices.joined(separator: "\n").filter { !$0.isWhitespace }.count
        == long.filter { !$0.isWhitespace }.count)
check("more than one slice", slices.count > 1)
check("a single overlong line is still split",
      MeetingSummarizer.slice(String(repeating: "x", count: 9_000)).count == 4)

print("dictation style by app")
check("terminal is code", DictationStyle.forApplication(bundleIdentifier: "com.apple.Terminal") == .code)
check("a JetBrains IDE is code", DictationStyle.forApplication(bundleIdentifier: "com.jetbrains.intellij") == .code)
check("slack is chat", DictationStyle.forApplication(bundleIdentifier: "com.tinyspeck.slackmacgap") == .chat)
check("mail is prose", DictationStyle.forApplication(bundleIdentifier: "com.apple.mail") == .prose)
check("an unknown app is prose", DictationStyle.forApplication(bundleIdentifier: nil) == .prose)

print("meeting export")
var meeting = Meeting(title: "Beta review", applicationName: "Zoom")
meeting.segments = [
    TranscriptSegment(source: .microphone, offset: 3, text: "We should ship on Friday."),
    TranscriptSegment(source: .system, offset: 11, text: "The installer will be ready Thursday."),
]
meeting.endedAt = meeting.startedAt.addingTimeInterval(742)
meeting.summary = MeetingSummary(
    headline: "Beta ships Friday",
    overview: "The team agreed a date.",
    keyPoints: ["Ship Friday"],
    decisions: ["Ship on Friday"],
    actionItems: [MeetingActionItem(task: "Finish the installer", owner: "Participants")],
    openQuestions: [],
    generatedAt: Date()
)
let markdown = meeting.markdown()
check("attributes both sides", meeting.plainTranscript.contains("You:") && meeting.plainTranscript.contains("Participants:"))
check("counts words", meeting.wordCount == 11)
check("formats the duration", DurationText.string(meeting.duration) == "12 min")
check("stamps the transcript", markdown.contains("**00:11 Participants:**"))
check("writes action items as checkboxes", markdown.contains("- [ ] Finish the installer — Participants"))
check("omits an empty section", !markdown.contains("Open questions"))

print("duration text")
check("seconds", DurationText.string(42) == "42s")
check("minutes", DurationText.string(742) == "12 min")
check("hours", DurationText.string(3_900) == "1h 5m")
check("signed", DurationText.string(-30) == "−30s")

print("dictation analytics")
let calendar = Calendar(identifier: .gregorian)
let now = Date(timeIntervalSince1970: 1_800_000_000)
func dictation(
    words: Int, audio: Double, process: Double,
    app: String? = "Mail", ago: TimeInterval = 0, corrections: Int = 0
) -> Dictation {
    Dictation(
        date: now.addingTimeInterval(-ago),
        text: Array(repeating: "word", count: words).joined(separator: " "),
        appName: app, bundleIdentifier: nil, style: .prose,
        audioSeconds: audio, processSeconds: process,
        corrections: corrections > 0
            ? [AppliedCorrection(from: "a", to: "b", count: corrections)] : nil
    )
}

// 40 words at 40 wpm is 60s of typing; it cost 20s held plus 1s waiting.
let saving = DictationAnalytics(
    entries: [dictation(words: 40, audio: 20, process: 1)],
    typingWordsPerMinute: 40, now: now, calendar: calendar)
check("counts words", saving.words == 40)
check("saves the difference", abs(saving.timeSaved - 39) < 0.001)
check("carries its assumption", saving.typingWordsPerMinute == 40)

// Three words is not worth the wait, and the figure should say so rather than clamp.
let losing = DictationAnalytics(
    entries: [dictation(words: 3, audio: 4, process: 2)],
    typingWordsPerMinute: 40, now: now, calendar: calendar)
check("goes negative honestly", losing.timeSaved < 0)

let mixed = DictationAnalytics(
    entries: [
        dictation(words: 40, audio: 20, process: 1, app: "Mail", corrections: 2),
        dictation(words: 10, audio: 10, process: 1, app: "Slack", ago: 60 * 60 * 24 * 3),
        dictation(words: 10, audio: 10, process: 3, app: "Mail", ago: 60 * 60 * 24 * 30),
    ],
    typingWordsPerMinute: 40, now: now, calendar: calendar)
check("median latency, not mean", mixed.medianLatency == 1)
check("counts only today", mixed.countToday == 1)
check("counts only the last week", mixed.wordsThisWeek == 50)
check("totals corrections", mixed.corrections == 2)
check("finds the busiest app", mixed.topApplication == "Mail" && mixed.topApplicationCount == 2)
check("a faster typist saves less",
      DictationAnalytics(entries: [dictation(words: 40, audio: 20, process: 1)],
                         typingWordsPerMinute: 100, now: now, calendar: calendar).timeSaved
      < saving.timeSaved)

print("meeting analytics")
func row(
    minutes: Double, yours: Int, others: Int, bothSides: Bool = true,
    actions: Int = 0, summarized: Bool = true, app: String? = "Zoom",
    ago: TimeInterval = 0, bytes: UInt64 = 1_000
) -> MeetingSummaryRow {
    var meeting = Meeting(
        title: "Call", startedAt: now.addingTimeInterval(-ago), applicationName: app)
    meeting.endedAt = meeting.startedAt.addingTimeInterval(minutes * 60)
    meeting.segments = [
        TranscriptSegment(source: .microphone, offset: 0,
                          text: Array(repeating: "a", count: yours).joined(separator: " ")),
    ]
    if bothSides {
        meeting.segments.append(
            TranscriptSegment(source: .system, offset: 1,
                              text: Array(repeating: "b", count: others).joined(separator: " ")))
    }
    if summarized {
        meeting.summary = MeetingSummary(
            headline: "H", overview: "O", keyPoints: [], decisions: [],
            actionItems: (0..<actions).map { MeetingActionItem(task: "t\($0)", owner: "o") },
            openQuestions: [], generatedAt: now)
    }
    return MeetingSummaryRow(meeting, bytes: bytes)
}

let solo = row(minutes: 10, yours: 100, others: 0, bothSides: false)
check("one-sided recording reports no share", solo.talkShare == nil)
check("two-sided recording reports a share",
      row(minutes: 10, yours: 30, others: 70).talkShare.map { abs($0 - 0.3) < 0.001 } == true)

let meetings = MeetingAnalytics(
    rows: [
        row(minutes: 60, yours: 100, others: 900, actions: 2),
        row(minutes: 20, yours: 50, others: 50, actions: 1, ago: 60 * 60 * 24 * 2),
        row(minutes: 30, yours: 10, others: 10, summarized: false, app: "Teams",
            ago: 60 * 60 * 24 * 30),
        solo,
    ],
    now: now, calendar: calendar)
check("totals duration", DurationText.string(meetings.totalDuration) == "2h 0m")
check("averages duration", DurationText.string(meetings.averageDuration) == "30 min")
check("finds the longest", DurationText.string(meetings.longest) == "1h 0m")
check("counts the last week", meetings.countThisWeek == 3)
check("totals action items", meetings.actionItems == 3)
check("counts what still needs summarizing", meetings.unsummarized == 1)
check("sums stored bytes", meetings.bytes == 4_000)
check("finds the busiest app", meetings.topApplication == "Zoom" && meetings.topApplicationCount == 3)
// 160 of 1120 words across the two-sided meetings, so about 14%. The one-sided meeting
// is excluded entirely. Averaging each meeting's own share instead — 10%, 50%, 50% —
// would have said 37%, which is the bug this check exists to catch.
check("weights talk share by words, excluding one-sided meetings",
      meetings.talkShare.map { abs($0 - 160.0 / 1120.0) < 0.001 } == true)
check("no share when nothing was two-sided",
      MeetingAnalytics(rows: [solo], now: now, calendar: calendar).talkShare == nil)
check("empty is empty", MeetingAnalytics(rows: [], now: now, calendar: calendar).isEmpty)

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
