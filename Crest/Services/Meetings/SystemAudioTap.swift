//
//  SystemAudioTap.swift
//  Crest
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

/// Captures everything the Mac is playing, so the other side of a call can be
/// transcribed without a bot joining the meeting.
///
/// ScreenCaptureKit rather than a CoreAudio process tap or a virtual audio device:
/// it is the only route that needs nothing installed, no kernel extension, no
/// `sudo`, and no rerouting of the user's output device. The cost is that the
/// permission it asks for is Screen & System Audio Recording, which reads as more
/// than it is — nothing here ever looks at pixels.
///
/// The stream is configured for the smallest legal video frame at the slowest legal
/// rate because `SCStreamConfiguration` has no audio-only mode: a display filter is
/// mandatory. Only the `.audio` output is attached, so no frame is ever delivered,
/// but the configuration still has to describe a valid one.
nonisolated final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.silvergrade.crest.systemaudio", qos: .userInitiated)

    private var converter: AudioFormatConverter?
    private var onBuffer: (@Sendable (AudioChunk) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onStop: (@Sendable (Error) -> Void)?

    /// True when the user has already granted screen recording, so the UI can ask for
    /// it up front rather than after they have started a meeting.
    ///
    /// Deliberately probes by asking for shareable content: `CGPreflightScreenCaptureAccess`
    /// answers for the older screen-capture path and does not track the newer grant
    /// reliably, and the only thing that matters here is whether the stream can start.
    static func hasPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onStop: @escaping @Sendable (Error) -> Void
    ) async throws {
        guard stream == nil else { return }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw SpeechEngineError.systemAudioDenied
        }
        guard let display = content.displays.first else {
            throw SpeechEngineError.systemAudioDenied
        }

        self.converter = AudioFormatConverter(outputFormat: outputFormat)
        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.onStop = onStop

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        // Without this, Crest's own alert sounds would be transcribed as if a
        // participant had said them, and the meter would jump on our own "Pop".
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // The smallest frame at the slowest rate. No video output is attached, so none
        // of this is ever produced — it exists because the configuration requires it.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 5

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()

        self.stream = stream
        VoiceLog.meeting.info("system audio capture started")
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        converter = nil
        onBuffer = nil
        onLevel = nil
        onStop = nil
        VoiceLog.meeting.info("system audio capture stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }

        onLevel?(AudioFormatConverter.level(of: pcm))
        guard let converted = converter?.convert(pcm) else { return }
        onBuffer?(AudioChunk(buffer: converted))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        VoiceLog.meeting.error("system audio stream stopped: \(error.localizedDescription, privacy: .public)")
        onStop?(error)
    }

    // MARK: - Sample conversion

    /// Copies one sample buffer into storage we own.
    ///
    /// The copy is not optional. `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:)` wraps
    /// memory owned by the `CMSampleBuffer`, which ScreenCaptureKit recycles the moment
    /// this callback returns — handing that buffer onward would hand over memory that is
    /// about to be someone else's audio.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              var asbd = description.audioStreamBasicDescription.map({ $0 }),
              let format = AVAudioFormat(streamDescription: &asbd)
        else { return nil }

        return try? sampleBuffer.withAudioBufferList { list, _ in
            guard let borrowed = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer)
            else { return nil as AVAudioPCMBuffer? }
            return AudioFormatConverter.copy(borrowed)
        }
    }
}
