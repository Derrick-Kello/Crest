//
//  SpeechEngine.swift
//  Crest
//

import AVFoundation
import Foundation
import OSLog
import Speech

/// A snapshot of the running transcript.
///
/// `text` is always the **full transcript so far**, not a delta — engines revise earlier
/// words as more audio arrives, so consumers replace rather than append.
nonisolated struct TranscriptionChunk: Sendable {
    /// Everything heard so far, committed words plus whatever the engine is currently
    /// guessing at. This is what a live HUD shows.
    let text: String
    /// The committed part only. It never shrinks and never gets rewritten, which is what
    /// makes it safe to diff — the meeting recorder builds its timeline out of the
    /// growth of this string, and would produce duplicated lines if it diffed `text`.
    let committedText: String
    /// True once the engine has emitted everything it will for this session.
    let isFinal: Bool
}

/// The seam that keeps the voice features engine-agnostic.
///
/// Apple's `SpeechAnalyzer` ships with macOS 26, needs no download and no dependency, so
/// it is the only implementation today. Anything else — Parakeet on the Neural Engine,
/// Whisper — implements this protocol and nothing above it changes.
nonisolated protocol SpeechEngine: Actor {
    /// Audio format the engine wants buffers in. The taps convert to it.
    func preferredInputFormat() async -> AVAudioFormat?

    /// Prepare models and open a session. Emits snapshots until `finish()` is called.
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error>

    /// Feed one buffer, already in `preferredInputFormat()`.
    func feed(_ chunk: AudioChunk) async

    /// Close the session and flush any pending final results.
    func finish() async
}

nonisolated enum SpeechEngineError: LocalizedError {
    case localeUnsupported(Locale)
    case modelInstallFailed(String)
    case noAudioFormat
    case microphoneDenied
    case systemAudioDenied

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let locale):
            "Dictation isn't available for \(locale.identifier) on this Mac."
        case .modelInstallFailed(let detail):
            "Couldn't install the speech model: \(detail)"
        case .noAudioFormat:
            "No compatible audio format available for the speech engine."
        case .microphoneDenied:
            "Microphone access is off. Turn it on in System Settings ▸ Privacy & Security ▸ Microphone."
        case .systemAudioDenied:
            "Screen & System Audio Recording is off. Turn it on in System Settings ▸ Privacy & Security."
        }
    }
}

/// Streaming on-device transcription via macOS 26's `SpeechAnalyzer` / `SpeechTranscriber`.
///
/// No model ships with Crest — the OS downloads and manages the assets, so the first
/// run for a locale may pause briefly while `AssetInstallationRequest` completes. Nothing
/// leaves the Mac at any point.
actor AppleSpeechEngine: SpeechEngine {
    private let locale: Locale
    /// Phrases to prime the recognizer with, captured up front because the store they
    /// come from lives on the main actor.
    private let biasPhrases: [String]

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// Text the engine has committed. Volatile results are shown on top of it but never
    /// stored, so the next revision replaces them cleanly.
    private var finalizedText = ""

    init(locale: Locale = Locale.current, biasPhrases: [String] = []) {
        self.locale = locale
        self.biasPhrases = biasPhrases
    }

    func preferredInputFormat() async -> AVAudioFormat? {
        let module = transcriber ?? Self.makeTranscriber(locale: locale)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechEngineError.localeUnsupported(locale)
        }

        let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            ?? Locale(identifier: "en-US")

        let transcriber = Self.makeTranscriber(locale: resolvedLocale)
        self.transcriber = transcriber

        try await Self.ensureModelInstalled(for: transcriber)

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        // Biasing the recognizer toward the vocabulary before it hears anything. This is
        // a nudge, not a guarantee — `VocabularyCorrector` is the pass that enforces
        // spelling — but it is free, and it catches things a post-hoc rewrite cannot,
        // like a name the engine would otherwise split into two ordinary words.
        //
        // It must be set before any audio arrives to affect recognition at all.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        if !biasPhrases.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = biasPhrases
            try? await analyzer.setContext(context)
            VoiceLog.speech.info("biasing with \(self.biasPhrases.count, privacy: .public) phrase(s)")
        }

        finalizedText = ""

        let (chunks, chunkContinuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()

        // Drains the transcriber's results into the simpler chunk stream above.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let snapshot = await self.absorb(result)
                    chunkContinuation.yield(TranscriptionChunk(
                        text: snapshot.display, committedText: snapshot.committed, isFinal: false
                    ))
                }
                let final = await self?.finalizedText ?? ""
                chunkContinuation.yield(TranscriptionChunk(
                    text: final, committedText: final, isFinal: true
                ))
                chunkContinuation.finish()
            } catch {
                VoiceLog.speech.error("results stream failed: \(error.localizedDescription, privacy: .public)")
                chunkContinuation.finish(throwing: error)
            }
        }

        try await analyzer.start(inputSequence: inputStream)
        VoiceLog.speech.info("SpeechAnalyzer started for \(resolvedLocale.identifier, privacy: .public)")

        return chunks
    }

    func feed(_ chunk: AudioChunk) async {
        inputContinuation?.yield(AnalyzerInput(buffer: chunk.buffer))
    }

    func finish() async {
        inputContinuation?.finish()
        inputContinuation = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            VoiceLog.speech.error("finalize failed: \(error.localizedDescription, privacy: .public)")
            await analyzer?.cancelAndFinishNow()
        }

        analyzer = nil
        transcriber = nil
        resultsTask = nil
    }

    // MARK: - Result accumulation

    /// Folds one result into the running transcript.
    ///
    /// Final results are committed; a volatile one is shown on top of the committed text
    /// but never stored, so the next revision replaces it cleanly instead of stuttering.
    private func absorb(_ result: SpeechTranscriber.Result) -> (display: String, committed: String) {
        let text = String(result.text.characters)
        let committed = finalizedText.trimmingCharacters(in: .whitespaces)
        guard result.isFinal else {
            return ((finalizedText + text).trimmingCharacters(in: .whitespaces), committed)
        }
        finalizedText += text
        let updated = finalizedText.trimmingCharacters(in: .whitespaces)
        return (updated, updated)
    }

    // MARK: - Setup

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // `.volatileResults` is what makes text appear while you are still talking.
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    private static func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let selected = transcriber.selectedLocales
        let alreadyThere = selected.allSatisfy { locale in
            installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        }
        guard !alreadyThere else { return }

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                VoiceLog.speech.info("downloading speech model…")
                try await request.downloadAndInstall()
                VoiceLog.speech.info("speech model installed")
            }
        } catch {
            throw SpeechEngineError.modelInstallFailed(error.localizedDescription)
        }
    }
}
