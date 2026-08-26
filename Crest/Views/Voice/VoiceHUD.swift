//
//  VoiceHUD.swift
//  Crest
//

import AppKit
import SwiftUI

/// The floating pill that appears while you hold the dictation key.
///
/// The single most important property here is that this panel **never becomes key**. If
/// it did, the user's text field would lose focus and `TextInjector` would have nothing
/// to insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false` — everything
/// else in the voice feature is replaceable, and this is not.
///
/// It is also the reason the HUD cannot be a SwiftUI `Window` scene: a window scene is
/// activatable by construction, and there is no way to opt a scene out of taking focus.
@MainActor
final class VoiceHUDPanel: NSPanel {
    init(service: DictationService) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 74),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        // Nothing here is clickable, and a panel that swallows clicks over the user's
        // document would be worse than useless.
        ignoresMouseEvents = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = NSHostingView(rootView: VoiceHUDView(service: service))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Parks the pill just above the Dock, centred on the active screen.
    ///
    /// `NSScreen.main` is the screen holding the *key window* — and an accessory app with
    /// a non-activating panel never has one, so it can be nil. Falling back to the screen
    /// under the pointer keeps the HUD where the user is looking rather than stranding it
    /// at the origin.
    func reposition() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 96))
    }

    func present() {
        // Every state change while active calls this. Without the early exit the panel
        // resets to alpha 0 and re-fades on each one, which reads as a flicker
        // mid-utterance.
        guard !isVisible || alphaValue < 1 else { return }

        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit always calls this on the main thread.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}

/// Owns the HUD panel and keeps it in step with the service.
///
/// A separate controller rather than logic inside the panel, because the panel is built
/// lazily: with dictation switched off, or simply not in use, Crest holds no window
/// and no SwiftUI view for it at all — the same reasoning as the command bar.
@MainActor
final class VoiceHUDController {
    static let shared = VoiceHUDController()

    private var panel: VoiceHUDPanel?
    private var observation: Task<Void, Never>?

    private init() {}

    /// Shows or hides the pill to match `phase`. Called from the service's observer.
    func update(service: DictationService) {
        let shouldShow: Bool = switch service.phase {
        case .idle: false
        default: true
        }

        guard shouldShow else {
            panel?.dismiss()
            return
        }

        let panel = panel ?? VoiceHUDPanel(service: service)
        self.panel = panel
        panel.present()
    }

    /// Releases the panel entirely. Called when dictation is switched off.
    func teardown() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - View

struct VoiceHUDView: View {
    @Bindable var service: DictationService

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.12), value: service.transcript)

                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if service.phase.isRecording {
                VoiceWaveform(level: service.level, isActive: service.phase == .listening)
                    .frame(width: 54, height: 22)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 360, height: 74)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            Circle()
                .fill(iconTint.opacity(0.16))
                .frame(width: 30, height: 30)
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconTint)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var iconName: String {
        switch service.phase {
        case .error: "exclamationmark.triangle.fill"
        case .notice: "info.circle.fill"
        case .rewriting: "wand.and.sparkles"
        case .finishing: "ellipsis"
        default: service.role == .command ? "wand.and.sparkles" : (service.isHandsFree ? "lock.fill" : "mic.fill")
        }
    }

    private var iconTint: Color {
        switch service.phase {
        case .error: .red
        case .notice: .orange
        default: .accentColor
        }
    }

    private var isError: Bool {
        if case .error = service.phase { return true }
        return false
    }

    private var label: String {
        switch service.phase {
        case .idle: ""
        case .starting: "Listening…"
        case .listening: service.transcript.isEmpty ? "Listening…" : service.transcript
        case .finishing: service.transcript.isEmpty ? "Transcribing…" : service.transcript
        case .rewriting: "Rewriting your selection…"
        case .error(let message): message
        case .notice(let message): message
        }
    }

    /// The line under the transcript. It says what will happen to the words, which is the
    /// one thing that is not obvious from the words themselves.
    private var caption: String? {
        switch service.phase {
        case .starting, .listening:
            var parts: [String] = []
            if let app = service.targetAppName { parts.append(app) }
            parts.append(service.activeStyle.title.lowercased())
            if service.isHandsFree {
                parts.append("hands-free — tap \(Preferences.pushToTalkKey.displayName) to stop")
            }
            return parts.joined(separator: " · ")
        case .rewriting, .finishing:
            return "on-device"
        default:
            return nil
        }
    }
}

/// Level-reactive bars. Each bar gets a fixed phase offset so the group ripples rather
/// than pumping in unison, which is what makes it read as a voice and not a progress bar.
struct VoiceWaveform: View {
    let level: Float
    let isActive: Bool
    var barCount = 10
    var tint: Color = .accentColor

    private static let phases: [Double] = (0..<24).map { index in
        // An irrational multiplier keeps the offsets from lining up into a visible period.
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5, height: height(for: index, at: time))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floorHeight: CGFloat = 2.5
        guard isActive else { return floorHeight }

        let phase = Self.phases[index % Self.phases.count]
        let wave = sin(time * 6.0 + phase * .pi * 2)
        let amplitude = CGFloat(max(0.04, level))
        // The wave rides on top of the level, so the bars still breathe during a pause.
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floorHeight + max(0, scaled) * 19
    }
}
