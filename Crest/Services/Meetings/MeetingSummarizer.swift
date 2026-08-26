//
//  MeetingSummarizer.swift
//  Crest
//

import Foundation
import FoundationModels
import OSLog

/// Notes taken from one slice of a transcript. The map half of the summarizer.
@Generable
nonisolated struct TranscriptNotes {
    @Guide(description: "The most important things said in this part of the meeting, one short sentence each. Six at most. Use the speaker labels that appear in the transcript.")
    var points: [String]

    @Guide(description: "Decisions that were actually settled in this part. Leave empty if nothing was decided.")
    var decisions: [String]

    @Guide(description: "Tasks somebody agreed to do. Leave empty if none were agreed.")
    var actions: [GeneratedAction]

    @Guide(description: "Questions that were raised and left unanswered. Leave empty if there were none.")
    var questions: [String]
}

@Generable
nonisolated struct GeneratedAction {
    @Guide(description: "What needs doing, as a short imperative sentence.")
    var task: String

    @Guide(description: "Who agreed to do it. Use 'Unassigned' when the transcript never says.")
    var owner: String
}

/// The finished summary. The reduce half.
@Generable
nonisolated struct GeneratedSummary {
    @Guide(description: "One sentence naming what this meeting was about. No more than twelve words.")
    var headline: String

    @Guide(description: "A short paragraph, three or four sentences, covering what happened and where it landed.")
    var overview: String

    @Guide(description: "The points worth remembering, one short sentence each. Eight at most, ordered by importance.")
    var keyPoints: [String]

    @Guide(description: "What was decided. Leave empty if nothing was.")
    var decisions: [String]

    @Guide(description: "Everything somebody agreed to do.")
    var actions: [GeneratedAction]

    @Guide(description: "Questions left open at the end.")
    var openQuestions: [String]
}

/// Turns a meeting transcript into a structured summary using Apple's on-device model.
///
/// **Why this is map-reduce rather than one call.** The on-device model has a small
/// context window — a few thousand tokens covering the prompt *and* the response — which
/// is a couple of minutes of talking, not an hour of it. Feeding a whole meeting in one
/// prompt does not produce a worse summary, it throws `exceededContextWindowSize` and
/// produces nothing. So the transcript is cut into slices that comfortably fit, each
/// slice is reduced to structured notes, and the notes are merged in a second pass. If
/// the notes themselves are too long to merge in one go, they are folded in rounds until
/// they fit.
///
/// **Why a fresh session per call.** A `LanguageModelSession` accumulates every prompt
/// and response in its transcript, and that transcript counts against the same window.
/// Reusing one session across twenty slices would run out of room somewhere in the
/// middle, in a way that looks like the model getting worse as the meeting goes on.
nonisolated struct MeetingSummarizer: Sendable {
    /// Characters per slice. Roughly 600 tokens of transcript, which leaves the rest of
    /// the window for the instructions and the generated notes. Conservative on purpose:
    /// the cost of a slice being too small is one extra pass, and the cost of one being
    /// too big is a thrown error and no summary at all.
    private static let sliceCharacters = 2_400

    /// Below this there is nothing to map — one pass straight to the summary.
    private static let singlePassCharacters = 2_000

    nonisolated enum SummaryError: LocalizedError {
        case unavailable(String)
        case emptyTranscript
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            case .emptyTranscript: "There's nothing in the transcript to summarize."
            case .failed(let detail): "Couldn't summarize this meeting: \(detail)"
            }
        }
    }

    /// - Parameter progress: called on an arbitrary executor with 0…1 as slices finish.
    func summarize(
        _ transcript: String,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> MeetingSummary {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SummaryError.emptyTranscript }

        guard ModelCleanup.isAvailable else {
            throw SummaryError.unavailable(
                ModelCleanup.unavailableReason ?? "The on-device model is unavailable."
            )
        }

        do {
            if text.count <= Self.singlePassCharacters {
                progress(0.5)
                let generated = try await Self.finalSummary(from: text, isRawTranscript: true)
                progress(1)
                return Self.convert(generated)
            }

            let slices = Self.slice(text)
            VoiceLog.meeting.info("summarizing \(text.count, privacy: .public) chars in \(slices.count, privacy: .public) slice(s)")

            var notes: [TranscriptNotes] = []
            for (index, slice) in slices.enumerated() {
                notes.append(try await Self.notes(from: slice))
                // The map pass is the long half, so it owns most of the progress bar.
                progress(Double(index + 1) / Double(slices.count) * 0.8)
            }

            var digest = Self.render(notes)
            // Fold until the merged notes fit in one prompt. A two-hour meeting produces
            // more notes than the window holds, and merging them is the same operation
            // as merging slices — so it is the same code, run again.
            var round = 0
            while digest.count > Self.sliceCharacters, round < 4 {
                round += 1
                var folded: [TranscriptNotes] = []
                for slice in Self.slice(digest) {
                    folded.append(try await Self.notes(from: slice, areNotes: true))
                }
                digest = Self.render(folded)
                VoiceLog.meeting.info("folded notes to \(digest.count, privacy: .public) chars (round \(round, privacy: .public))")
            }

            progress(0.9)
            let generated = try await Self.finalSummary(from: digest, isRawTranscript: false)
            progress(1)
            return Self.convert(generated)
        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.failed(Self.describe(error))
        }
    }

    // MARK: - Map

    private static func notes(from slice: String, areNotes: Bool = false) async throws -> TranscriptNotes {
        let subject = areNotes
            ? "notes already taken from a meeting transcript"
            : "part of a meeting transcript"

        let session = LanguageModelSession(instructions: """
            You take notes from \(subject). You are a note taker, not a participant.

            Rules:
            - Only record what is actually in the text. Never infer, guess, or fill gaps.
            - Attribute using the speaker labels in the text ("You", "Participants").
            - Leave a list empty rather than padding it. Most short stretches of a \
            meeting contain no decisions and no action items, and saying so is correct.
            - Keep every line short enough to scan.
            - Speech-to-text makes mistakes. If a passage is garbled, skip it rather than \
            guessing at what it meant.
            """)

        let response = try await session.respond(
            to: "\(areNotes ? "Merge these notes" : "Take notes from this transcript"):\n\n\(slice)",
            generating: TranscriptNotes.self,
            options: GenerationOptions(temperature: 0.2)
        )
        return response.content
    }

    // MARK: - Reduce

    private static func finalSummary(
        from text: String,
        isRawTranscript: Bool
    ) async throws -> GeneratedSummary {
        let session = LanguageModelSession(instructions: """
            You write the summary of a meeting from \(isRawTranscript ? "its transcript" : "notes taken during it").

            Rules:
            - Only use what is in the text. Never infer, guess, or invent an owner, a \
            date, or a decision that was not stated.
            - Write plainly. No preamble, no closing remarks, no "in this meeting".
            - Attribute using the speaker labels in the text ("You", "Participants").
            - Leave a list empty rather than padding it.
            - Never address the reader or offer to help.
            """)

        let response = try await session.respond(
            to: "Summarize this:\n\n\(text)",
            generating: GeneratedSummary.self,
            options: GenerationOptions(temperature: 0.2)
        )
        return response.content
    }

    // MARK: - Plumbing

    /// Splits on line boundaries so a slice never begins mid-sentence, falling back to a
    /// hard cut only for a single line longer than a whole slice.
    static func slice(_ text: String) -> [String] {
        var slices: [String] = []
        var current = ""

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.count > sliceCharacters {
                if !current.isEmpty {
                    slices.append(current)
                    current = ""
                }
                var remainder = Substring(line)
                while !remainder.isEmpty {
                    let end = remainder.index(
                        remainder.startIndex,
                        offsetBy: min(sliceCharacters, remainder.count)
                    )
                    slices.append(String(remainder[..<end]))
                    remainder = remainder[end...]
                }
                continue
            }

            if current.count + line.count + 1 > sliceCharacters, !current.isEmpty {
                slices.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }

        if !current.isEmpty { slices.append(current) }
        return slices
    }

    /// Renders notes back into text the model can read for the next pass.
    private static func render(_ notes: [TranscriptNotes]) -> String {
        var lines: [String] = []
        for note in notes {
            lines.append(contentsOf: note.points.map { "- \($0)" })
            lines.append(contentsOf: note.decisions.map { "- Decided: \($0)" })
            lines.append(contentsOf: note.actions.map { "- Action: \($0.task) (\($0.owner))" })
            lines.append(contentsOf: note.questions.map { "- Open: \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func convert(_ generated: GeneratedSummary) -> MeetingSummary {
        MeetingSummary(
            headline: generated.headline.trimmingCharacters(in: .whitespacesAndNewlines),
            overview: generated.overview.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPoints: clean(generated.keyPoints),
            decisions: clean(generated.decisions),
            actionItems: generated.actions.compactMap { action in
                let task = action.task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { return nil }
                let owner = action.owner.trimmingCharacters(in: .whitespacesAndNewlines)
                return MeetingActionItem(task: task, owner: owner.isEmpty ? "Unassigned" : owner)
            },
            openQuestions: clean(generated.openQuestions),
            generatedAt: Date()
        )
    }

    private static func clean(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The reasons worth telling apart: a context overflow means the slicing is wrong and
    /// is worth reporting as a bug, while unavailable assets mean Apple Intelligence is
    /// simply off and the user can fix it.
    private static func describe(_ error: Error) -> String {
        guard let error = error as? LanguageModelSession.GenerationError else {
            return error.localizedDescription
        }
        switch error {
        case .exceededContextWindowSize: return "a section was too long for the on-device model"
        case .assetsUnavailable: return "the on-device model isn't downloaded yet"
        case .guardrailViolation: return "the on-device model declined this content"
        case .rateLimited: return "the on-device model is busy"
        case .refusal: return "the on-device model declined this content"
        default: return error.localizedDescription
        }
    }
}
