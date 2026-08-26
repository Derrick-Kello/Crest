//
//  ColorPickerService.swift
//  Crest
//

import AppKit
import Foundation
import SwiftUI

enum ColorFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case hex = "HEX"
    case rgb = "RGB"
    case hsl = "HSL"
    case swiftUI = "SwiftUI"

    var id: String { rawValue }
}

struct PickedColor: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let red: Double
    let green: Double
    let blue: Double
    let pickedAt: Date

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    private var bytes: (Int, Int, Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    func string(in format: ColorFormat, bareHex: Bool = false) -> String {
        let (r, g, b) = bytes
        switch format {
        case .hex:
            let hex = String(format: "%02X%02X%02X", r, g, b)
            return bareHex ? hex : "#\(hex)"
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = Self.hsl(red: red, green: green, blue: blue)
            return "hsl(\(Int(h.rounded())), \(Int(s.rounded()))%, \(Int(l.rounded()))%)"
        case .swiftUI:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
        }
    }

    private static func hsl(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum

        guard delta > 0 else { return (0, 0, lightness * 100) }

        let saturation = lightness > 0.5
            ? delta / (2 - maximum - minimum)
            : delta / (maximum + minimum)

        var hue: Double
        switch maximum {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60

        return (hue, saturation * 100, lightness * 100)
    }
}

/// Screen color picking via `NSColorSampler`.
///
/// The system sampler is used deliberately: it is the one path that reads screen
/// pixels without the app itself holding Screen Recording permission, because the
/// magnifier is drawn and sampled by the OS on the app's behalf.
@MainActor
@Observable
final class ColorPickerService {
    static let shared = ColorPickerService()

    private(set) var recent: [PickedColor] = []
    var format: ColorFormat {
        didSet { Preferences.colorFormat = format }
    }
    var bareHex: Bool {
        didSet { Preferences.colorBareHex = bareHex }
    }

    private let recentLimit = 12
    private var sampler: NSColorSampler?

    private init() {
        format = Preferences.colorFormat
        bareHex = Preferences.colorBareHex
        recent = Preferences.recentColors
    }

    /// Picks a color and copies it in the chosen format. Returns the formatted
    /// string so the caller can show what landed on the clipboard.
    func pick() async -> String? {
        let sampler = NSColorSampler()
        self.sampler = sampler

        let color: NSColor? = await withCheckedContinuation { continuation in
            sampler.show { picked in
                continuation.resume(returning: picked)
            }
        }
        self.sampler = nil

        guard let color,
              let srgb = color.usingColorSpace(.sRGB) else { return nil }

        let picked = PickedColor(
            id: UUID(),
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            pickedAt: .now
        )

        recent.insert(picked, at: 0)
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
        Preferences.recentColors = recent

        let text = picked.string(in: format, bareHex: bareHex)
        copy(text)
        return text
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copy(_ color: PickedColor) {
        copy(color.string(in: format, bareHex: bareHex))
    }

    func clearRecent() {
        recent = []
        Preferences.recentColors = []
    }
}
