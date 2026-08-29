//
//  AccessibilityBridge.swift
//  Crest
//

import AppKit
import ApplicationServices

/// Typed reads and writes against the Accessibility API.
///
/// macOS has no way to replace the window server, so a tiling window manager here
/// is not a compositor — it is a program that asks other applications to move
/// their own windows, one `AXUIElement` at a time. Everything the tiler does
/// bottoms out in this file.
///
/// The API is untyped C: attributes are strings, values are `CFTypeRef`, and a
/// wrong cast is a crash rather than a compile error. So the casts live here once,
/// behind functions that return optionals, and the rest of the tiler never touches
/// `AXUIElementCopyAttributeValue` directly.
nonisolated enum AX {

    // MARK: - Permission

    /// Whether the user has granted Accessibility, checked without prompting.
    ///
    /// Called on every layout pass, so it must not be the prompting variant: that
    /// one raises a system dialog, and raising it sixty times a second is not a
    /// recoverable state for the machine.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility, showing the system prompt when it has not been
    /// answered yet. Returns the trust state as it stands *now* — granting is
    /// asynchronous and happens in System Settings, so a `false` here means
    /// "not yet", not "refused".
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens the pane the user has to flip the switch in. The prompt's own button
    /// does this too, but the prompt only ever appears once per install — after
    /// that, this is the only way back.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Diagnosing a permission that looks granted

    /// Why Accessibility is not working.
    ///
    /// The case that matters is `staleRecord`, and it is the reason this type
    /// exists at all: macOS shows one row per *application* in the Accessibility
    /// list, but grants permission to one specific *binary*. When those disagree
    /// the switch reads as on and the API still refuses, and the user is left
    /// toggling a control that was never the problem.
    enum Trust: Equatable {
        case granted
        /// No record yet. Asking will show the system prompt.
        case notAsked
        /// macOS is holding a grant for a build of Crest that is not this one, so
        /// asking again shows no prompt and changes nothing.
        case staleRecord(grantedCopy: String?)
    }

    static func diagnose() -> Trust {
        if isTrusted { return .granted }

        // An ad-hoc signature has no certificate and no team behind it, so the
        // only thing TCC can pin a grant to is the code directory hash — which
        // every single rebuild changes. A build signed this way cannot keep a
        // permission across a compile, and cannot inherit one from the copy in
        // /Applications either.
        guard isAdHocSigned || otherInstalledCopy != nil else { return .notAsked }
        return .staleRecord(grantedCopy: otherInstalledCopy)
    }

    /// Another copy of Crest installed elsewhere, which is most likely the one the
    /// switch in System Settings belongs to.
    static var otherInstalledCopy: String? {
        let running = Bundle.main.bundleURL.standardizedFileURL
        let installed = URL(fileURLWithPath: "/Applications/Crest.app")
        guard FileManager.default.fileExists(atPath: installed.path),
              installed.standardizedFileURL != running
        else { return nil }
        return installed.path
    }

    /// Whether this build carries only an ad-hoc signature.
    ///
    /// Read from the binary itself rather than assumed from the path, because it
    /// is the signature and not the location that decides whether a grant
    /// survives — an ad-hoc copy dragged into /Applications is no more durable
    /// there than it was in DerivedData.
    static var isAdHocSigned: Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code
        else { return false }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signing = info as? [String: Any]
        else { return false }

        // A real identity puts a certificate chain in here. Ad-hoc signing does not.
        let certificates = signing[kSecCodeInfoCertificates as String] as? [Any]
        return certificates?.isEmpty ?? true
    }

    /// Forgets every Accessibility decision recorded for this bundle id, so the
    /// system will ask again from scratch.
    ///
    /// The blunt instrument, and the only one available: there is no API to remove
    /// one stale entry while keeping the rest, and no way to ask TCC which binary
    /// a grant belongs to. It revokes the permission for every copy of Crest on
    /// the Mac, which is why nothing calls this without the user asking for it.
    @discardableResult
    static func resetTrust() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return (try? ProcessRunner.run("/usr/bin/tccutil", arguments: ["reset", "Accessibility", bundleID])) != nil
    }

    // MARK: - Attributes

    /// Reads an attribute whose value is a plain CoreFoundation object.
    static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? T
    }

    /// Reads an attribute whose value is boxed in an `AXValue` — the geometry
    /// ones, which do not bridge to a Swift type on their own.
    static func copyValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType, _ empty: T) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }

        let boxed = unsafeDowncast(raw as AnyObject, to: AXValue.self)
        guard AXValueGetType(boxed) == type else { return nil }

        var out = empty
        guard AXValueGetValue(boxed, type, &out) else { return nil }
        return out
    }

    /// Reads an element-valued attribute, such as the focused window of an app.
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(raw as AnyObject, to: AXUIElement.self)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let raw: [AnyObject] = copy(element, attribute) else { return [] }
        return raw.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID()
                ? unsafeDowncast(item, to: AXUIElement.self)
                : nil
        }
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    /// Whether an attribute can be written at all.
    ///
    /// Worth asking before trying: a window that reports its size as unsettable is
    /// a window the tiler must leave floating — System Settings and most open/save
    /// sheets are in this category — and finding that out by attempting the write
    /// and watching nothing happen makes the layout silently wrong instead.
    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    // MARK: - Geometry

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = copyValue(window, kAXPositionAttribute as String, .cgPoint, CGPoint.zero),
              let size = copyValue(window, kAXSizeAttribute as String, .cgSize, CGSize.zero)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Moves and resizes a window.
    ///
    /// Position is written twice, once on each side of the size. This is not
    /// superstition: a window with a minimum size that is currently larger than
    /// the target rect will clamp the resize, and a window near a screen edge will
    /// have its move clamped by the size it still had at the time. Setting
    /// position, then size, then position again converges for both cases, which
    /// single-pass ordering does not. Every mature macOS tiler does this.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: AXUIElement) -> Bool {
        var origin = frame.origin
        var size = frame.size

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        set(window, kAXPositionAttribute as String, positionValue)
        let resized = set(window, kAXSizeAttribute as String, sizeValue)
        set(window, kAXPositionAttribute as String, positionValue)
        return resized
    }

    // MARK: - Identity

    /// The window server's id for an accessibility element.
    ///
    /// `_AXUIElementGetWindow` is private API, and it is the only way to correlate
    /// an `AXUIElement` with anything else on the system — the public API gives a
    /// window no stable identity at all, so without this a window cannot be
    /// remembered across two passes of the enumerator, let alone assigned to a
    /// workspace. Every tiler on macOS uses it.
    ///
    /// Looked up through `dlsym` rather than declared, so that the day Apple
    /// removes the symbol Crest falls back to titles instead of failing to launch.
    static func windowID(of window: AXUIElement) -> CGWindowID? {
        guard let function = getWindowID else { return nil }
        var id: CGWindowID = 0
        guard function(window, &id) == .success, id != 0 else { return nil }
        return id
    }

    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindowID: GetWindowFunction? = {
        // RTLD_DEFAULT — search every loaded image, which is where HIServices is.
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()
}
