//
//  MeetingHUD.swift
//  Crest
//

import AppKit
import SwiftUI

/// The small badge that sits in the corner for as long as a meeting is being recorded.
///
/// Non-activating for the same reason the dictation HUD is: you are in a call, in
/// another app, and a recording indicator that steals focus when you glance at it would
/// take your camera view or your screen share with it. Unlike the dictation HUD this one
/// does accept clicks — the stop button has to be reachable without hunting through the
/// menu bar — which a non-activating panel can do without ever becoming key.
@MainActor
final class MeetingHUDPanel: NSPanel {
    init(recorder: MeetingRecorder) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = NSHostingView(rootView: MeetingHUDView(recorder: recorder))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Top-right, under the menu bar: the corner every other recording indicator on macOS
    /// uses, and the one least likely to sit over a call window's controls.
    func reposition() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: visible.maxX - frame.width - 16,
            y: visible.maxY - frame.height - 12
        ))
    }

    func present() {
        guard !isVisible || alphaValue < 1 else { return }
        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}

@MainActor
final class MeetingHUDController {
    static let shared = MeetingHUDController()

    private var panel: MeetingHUDPanel?

    private init() {}

    func update(recorder: MeetingRecorder) {
        let shouldShow = recorder.state.isRecording
            || recorder.state.isSummarizing
            || recorder.suggestion != nil

        guard shouldShow else {
            panel?.dismiss()
            return
        }
        let panel = panel ?? MeetingHUDPanel(recorder: recorder)
        self.panel = panel
        panel.present()
    }

    func teardown() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - View

struct MeetingHUDView: View {
    @Bindable var recorder: MeetingRecorder

    var body: some View {
        HStack(spacing: 10) {
            if let application = recorder.suggestion, !recorder.state.isRecording {
                offer(application: application)
            } else if recorder.state.isSummarizing {
                summarizing
            } else {
                recording
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 300, height: 56)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        }
    }

    @ViewBuilder
    private var recording: some View {
        // A pulsing dot rather than a static one: an indicator that could be a stale
        // window is not an indicator, and this is the only thing telling the user a
        // microphone is live.
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .phaseAnimator([0.35, 1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.9) }

        VStack(alignment: .leading, spacing: 3) {
            Text(DurationText.string(recorder.elapsed))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()

            HStack(spacing: 6) {
                meter(level: recorder.micLevel, symbol: "mic.fill", isOn: Preferences.meetingCaptureMicrophone)
                meter(
                    level: recorder.systemLevel,
                    symbol: "speaker.wave.2.fill",
                    isOn: Preferences.meetingCaptureSystemAudio && recorder.systemAudioWarning == nil
                )
            }
        }

        Spacer(minLength: 0)

        Button {
            recorder.stop()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.red))
        }
        .buttonStyle(.plain)
        .help("Stop recording and summarize")
        .accessibilityLabel("Stop recording")
    }

    /// The offer to take notes, shown when a call app starts using the microphone.
    ///
    /// Deliberately two buttons and no third state: "not now" silences it for this call
    /// and nothing else, so declining costs one click and never has to be repeated.
    @ViewBuilder
    private func offer(application: String) -> some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tint)

        VStack(alignment: .leading, spacing: 1) {
            Text("Take notes?")
                .font(.system(size: 12, weight: .semibold))
            Text("\(application) is using the mic")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        Spacer(minLength: 0)

        Button("Not now") { recorder.dismissSuggestion() }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        Button("Record") { recorder.acceptSuggestion() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }

    @ViewBuilder
    private var summarizing: some View {
        let fraction: Double = if case .summarizing(let value) = recorder.state { value } else { 0 }

        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tint)

        VStack(alignment: .leading, spacing: 4) {
            Text("Writing the summary")
                .font(.system(size: 12, weight: .medium))
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }

    private func meter(level: Float, symbol: String, isOn: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8))
                .foregroundStyle(isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            Capsule()
                .fill(.quaternary)
                .frame(width: 36, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.tint)
                        .frame(width: isOn ? 36 * CGFloat(min(1, max(0, level))) : 0)
                }
        }
    }
}
