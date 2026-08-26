//
//  AudioPipeline.swift
//  Crest
//

import AVFoundation
import Foundation
import OSLog

nonisolated enum VoiceLog {
    static let audio = Logger(subsystem: "com.silvergrade.crest", category: "VoiceAudio")
    static let speech = Logger(subsystem: "com.silvergrade.crest", category: "VoiceSpeech")
    static let inject = Logger(subsystem: "com.silvergrade.crest", category: "VoiceInject")
    static let meeting = Logger(subsystem: "com.silvergrade.crest", category: "Meeting")
}

/// One buffer of captured audio, in transit from an audio thread to a speech engine.
///
/// `AVAudioPCMBuffer` is not `Sendable`, and `AVAudioEngine` recycles the buffer it
/// hands a tap the moment the callback returns. The unchecked conformance is only sound
/// because every producer here allocates *fresh* storage for each chunk and never
/// touches it again after handing it over — never build one around a borrowed buffer.
nonisolated struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Where a chunk of audio came from. The meeting recorder runs two captures at once and
/// this is what keeps their transcripts attributable without a diarization model.
nonisolated enum AudioSource: String, Codable, Sendable, CaseIterable {
    /// The microphone: you.
    case microphone
    /// Everything the Mac is playing: the other people in the call.
    case system

    var speakerLabel: String {
        switch self {
        case .microphone: "You"
        case .system: "Participants"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone: "mic"
        case .system: "speaker.wave.2"
        }
    }
}

/// Converts arbitrary capture formats to whatever the speech engine asked for.
///
/// Both taps need this and neither can know its input format ahead of time: the
/// microphone reports the device's native rate, and ScreenCaptureKit picks its own. The
/// converter is built lazily on the first buffer and rebuilt if the format changes
/// mid-stream, which happens when the user switches input devices while recording.
///
/// Lives entirely on one audio thread, hence `@unchecked Sendable` with no locking.
nonisolated final class AudioFormatConverter: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    /// - Returns: a freshly allocated buffer in the output format, or nil if the buffer
    ///   was empty or the conversion failed.
    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }

        if buffer.format == outputFormat {
            return Self.copy(buffer)
        }

        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            VoiceLog.audio.info("converting \(buffer.format.sampleRate, privacy: .public)Hz × \(buffer.format.channelCount, privacy: .public)ch → \(self.outputFormat.sampleRate, privacy: .public)Hz × \(self.outputFormat.channelCount, privacy: .public)ch")
        }
        guard let converter else { return nil }

        // Output frame count scales with the sample-rate ratio; rounded up, with slack,
        // so a conversion is never clipped short.
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        // The input block runs synchronously inside `convert`, on this thread.
        nonisolated(unsafe) let input = buffer
        let consumed = Latch()
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            guard !consumed.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }

        if let error {
            VoiceLog.audio.error("conversion failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard status != .error, converted.frameLength > 0 else { return nil }
        return converted
    }

    /// Deep-copies a tap buffer into storage we own.
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }

        return copy
    }

    /// A 0…1 loudness reading for the meter. Handles float and 16-bit buffers, because
    /// the microphone hands back float and a converted engine buffer is int16.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<count {
                let sample = channel[index]
                sum += sample * sample
            }
        } else if let channel = buffer.int16ChannelData?[0] {
            for index in 0..<count {
                let sample = Float(channel[index]) / 32768
                sum += sample * sample
            }
        } else {
            return 0
        }

        let rms = (sum / Float(count)).squareRoot()
        // Maps roughly -50…0 dBFS onto 0…1, so quiet speech still moves the meter.
        let decibels = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (decibels + 50) / 50))
    }

    /// One-shot flag, only touched from the audio thread inside a synchronous call.
    private final class Latch: @unchecked Sendable {
        private var fired = false
        /// - Returns: the value *before* this call, then latches to `true`.
        func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }
}

/// Microphone capture with on-the-fly conversion to whatever format the engine wants.
///
/// The tap runs on a real-time audio thread, so everything it touches lives behind
/// `nonisolated(unsafe)` and is only ever mutated from that one thread.
nonisolated final class MicrophoneTap: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private nonisolated(unsafe) var converter: AudioFormatConverter?
    private var isRunning = false

    /// Called on the audio thread with each converted buffer.
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    /// Called on the audio thread with a 0…1 level, for the meter.
    private nonisolated(unsafe) var onLevel: (@Sendable (Float) -> Void)?

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        guard !isRunning else { return }

        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.converter = AudioFormatConverter(outputFormat: outputFormat)

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        VoiceLog.audio.info("microphone started — native \(nativeFormat.sampleRate, privacy: .public)Hz")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil
        onBuffer = nil
        onLevel = nil
        VoiceLog.audio.info("microphone stopped")
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        onLevel?(AudioFormatConverter.level(of: buffer))
        guard let converted = converter?.convert(buffer) else { return }
        onBuffer?(AudioChunk(buffer: converted))
    }
}
