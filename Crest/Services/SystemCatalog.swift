//
//  SystemCatalog.swift
//  Crest
//

import AppKit
import Foundation

/// Everything searchable that is not an installed application: System Settings
/// panes, the system commands a launcher is expected to run, and Crest's own
/// tools. All of it is derived locally — a directory listing and three static
/// tables — so the command bar works with no network and nothing to sync.
nonisolated enum SystemCatalog {

    static func scan() -> [CatalogItem] {
        settingsPanes() + systemCommands() + tools()
    }

    // MARK: - System Settings

    /// System Settings panes, read from the ExtensionKit bundles that back them.
    ///
    /// macOS 13 replaced the old `.prefPane` plugins with app extensions, and the
    /// leftover `.prefPane` stubs no longer carry usable metadata — several have
    /// no `Info.plist` at all. The extensions do, and their bundle identifiers are
    /// exactly what the `x-apple.systempreferences:` URL scheme expects.
    static func settingsPanes() -> [CatalogItem] {
        let directory = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [CatalogItem] = []
        var seen: Set<String> = []

        for url in entries where url.pathExtension == "appex" {
            guard let info = readPlist(at: url.appending(path: "Contents/Info.plist")),
                  let bundleID = info["CFBundleIdentifier"] as? String,
                  isSettingsPane(bundleID)
            else { continue }

            let name = displayName(for: bundleID, info: info)
            guard seen.insert(name.lowercased()).inserted else { continue }

            items.append(CatalogItem(
                id: "setting:" + bundleID,
                title: name,
                subtitle: "System Settings",
                category: .setting,
                symbolName: symbol(for: name),
                keys: CatalogItem.keys(
                    title: name,
                    aliases: paneAliases[name.lowercased()] ?? [],
                    // So "settings wifi" and "preferences sound" both work.
                    weak: ["system settings", "preferences", bundleID]
                ),
                action: .openURL("x-apple.systempreferences:" + bundleID)
            ))
        }
        return items.sorted { $0.title < $1.title }
    }

    /// The extension directory holds 200-odd bundles, most of them thumbnailers
    /// and intent handlers. The settings panes are the ones whose identifier says
    /// "settings" and ends in an extension suffix — matched case-insensitively,
    /// because Apple ships both `Network-Settings.extension` and
    /// `wifi-settings-extension` and only one of them follows the house style.
    private static func isSettingsPane(_ bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        guard !lower.contains("intents"), !lower.contains("widget"),
              !lower.contains("followup"), !lower.contains("controls")
        else { return false }

        guard !excludedPaneIDs.contains(bundleID) else { return false }
        if knownPaneIDs.contains(bundleID) { return true }
        if lower.hasPrefix("com.apple.systempreferences.") { return true }
        return lower.contains("settings")
            && (lower.hasSuffix(".extension") || lower.hasSuffix("-extension"))
    }

    /// A handful of panes carry an internal name in `CFBundleDisplayName`
    /// ("PowerPreferences", "WiFiSettings"). Those get corrected; the rest are
    /// already the name shown in the System Settings sidebar.
    private static func displayName(for bundleID: String, info: [String: Any]) -> String {
        if let override = nameOverrides[bundleID] { return override }

        let raw = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleID

        // "Accessibility Settings Extension" and "LockScreen" are both internal
        // names; the sidebar calls them "Accessibility" and "Lock Screen". Split
        // the camel case, then drop the boilerplate suffixes.
        return trimSuffixes(splitCamelCase(raw))
    }

    /// Every pane here is a setting inside an extension, so saying so in the title
    /// is noise that pushes the part the user typed off the end of the row.
    private static func trimSuffixes(_ name: String) -> String {
        var result = name
        for suffix in [" Extension", " Settings", " Preferences", " Pane"] where result.hasSuffix(suffix) {
            let trimmed = String(result.dropLast(suffix.count))
            if !trimmed.isEmpty { result = trimmed }
        }
        return result
    }

    /// "LockScreen" → "Lock Screen". Names a split would mangle ("WiFiSettings"
    /// would become "Wi Fi Settings") are handled by `nameOverrides` instead.
    private static func splitCamelCase(_ raw: String) -> String {
        guard !raw.contains(" ") else { return raw }
        var result = ""
        var previousWasLower = false
        for character in raw {
            if character.isUppercase && previousWasLower { result.append(" ") }
            result.append(character)
            previousWasLower = character.isLowercase || character.isNumber
        }
        return result
    }

    private static let nameOverrides: [String: String] = [
        "com.apple.Battery-Settings.extension": "Battery",
        "com.apple.wifi.WiFiSettingsUI": "Wi-Fi",
        "com.apple.Wi-Fi-Settings.extension": "Wi-Fi",
        "com.apple.systempreferences.AppleIDSettings": "Apple Account",
        "com.apple.systempreferences.InternationalSettingsExtension": "Language & Region",
        "com.apple.systempreferences.KeyboardSettingsExtension": "Keyboard",
        "com.apple.Print-Scan-Settings.extension": "Printers & Scanners",
        "com.apple.CD-DVD-Settings.extension": "CDs & DVDs",
        "com.apple.AirDrop-Handoff-Settings.extension": "AirDrop & Handoff",
        "com.apple.Date-Time-Settings.extension": "Date & Time",
        "com.apple.wifi-settings-extension": "Wi-Fi",
        "com.apple.HeadphoneSettings": "Headphones",
        "com.apple.ControlCenter-Settings.extension": "Control Center",
        "com.apple.Lock-Screen-Settings.extension": "Lock Screen",
        "com.apple.Login-Items-Settings.extension": "Login Items",
        "com.apple.Software-Update-Settings.extension": "Software Update",
        "com.apple.Screen-Time-Settings.extension": "Screen Time",
        "com.apple.Game-Center-Settings.extension": "Game Center",
        "com.apple.Game-Controller-Settings.extension": "Game Controllers",
        "com.apple.Internet-Accounts-Settings.extension": "Internet Accounts",
        "com.apple.Users-Groups-Settings.extension": "Users & Groups",
        "com.apple.Privacy-Settings.extension": "Privacy & Security",
        "com.apple.Desktop-Settings.extension": "Desktop & Dock",
        "com.apple.Touch-ID-Settings.extension": "Touch ID & Password",
        "com.apple.Transfer-Reset-Settings.extension": "Transfer or Reset",
    ]

    /// Real panes that are never the answer to a launcher query: an enterprise
    /// management shim and a carrier-coverage page with an unreadable name.
    private static let excludedPaneIDs: Set<String> = [
        "com.apple.Coverage-Settings.extension",
        "com.apple.CoverageSettings",
    ]

    /// Panes worth indexing whose identifiers do not follow either naming rule.
    private static let knownPaneIDs: Set<String> = [
        "com.apple.BluetoothSettings",
        "com.apple.wifi-settings-extension",
        "com.apple.HeadphoneSettings",
        "com.apple.MediaExtensions-Settings",
    ]

    /// What people type when they want a pane but do not know Apple's name for it.
    private static let paneAliases: [String: [String]] = [
        "displays": ["monitor", "resolution", "screen", "brightness", "hdr", "refresh rate"],
        "sound": ["audio", "volume", "output", "input", "speakers", "microphone"],
        "network": ["internet", "ethernet", "vpn", "proxy", "dns", "ip"],
        "wi-fi": ["wifi", "wireless", "network", "internet"],
        "bluetooth": ["pairing", "devices", "headphones"],
        "battery": ["power", "energy saver", "low power mode", "charge"],
        "keyboard": ["shortcuts", "key repeat", "input sources", "text replacement"],
        "trackpad": ["gestures", "scrolling", "tap to click"],
        "mouse": ["pointer", "scrolling", "tracking speed"],
        "appearance": ["dark mode", "light mode", "theme", "accent colour", "accent color"],
        "general": ["about", "storage", "software update", "sharing"],
        "privacy": ["security", "permissions", "camera", "microphone", "full disk access",
                    "gatekeeper", "firewall", "filevault", "privacy & security"],
        "privacy & security": ["permissions", "camera", "microphone", "full disk access",
                               "gatekeeper", "firewall", "filevault"],
        "notifications": ["alerts", "banners", "do not disturb"],
        "focus": ["do not disturb", "dnd", "modes"],
        "screen time": ["limits", "downtime", "parental controls"],
        "users & groups": ["accounts", "login", "guest user"],
        "login items": ["startup", "launch at login", "autostart", "open at login"],
        "desktop & dock": ["dock", "hot corners", "mission control", "stage manager", "menu bar"],
        "lock screen": ["screensaver", "screen saver", "require password"],
        "wallpaper": ["background", "desktop picture"],
        "accessibility": ["voiceover", "zoom", "contrast", "reduce motion"],
        "software update": ["updates", "upgrade", "macos update"],
        "storage": ["disk space", "free space", "manage storage"],
        "printers & scanners": ["printer", "print", "scan", "airprint"],
        "date & time": ["clock", "timezone", "time zone"],
        "language & region": ["locale", "translation", "units", "currency"],
        "control center": ["menu bar", "status bar", "icons"],
        "siri": ["assistant", "voice"],
        "spotlight": ["search", "indexing", "privacy"],
    ]

    private static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case "displays": "display"
        case "sound": "speaker.wave.2"
        case "network": "network"
        case "wi-fi": "wifi"
        case "bluetooth": "dot.radiowaves.right"
        case "battery": "battery.100"
        case "keyboard": "keyboard"
        case "trackpad": "rectangle.and.hand.point.up.left"
        case "mouse": "computermouse"
        case "appearance": "paintpalette"
        case "notifications": "bell.badge"
        case "focus": "moon"
        case "accessibility": "figure.arms.open"
        case "privacy & security": "hand.raised"
        case "software update": "arrow.triangle.2.circlepath"
        case "storage": "internaldrive"
        case "printers & scanners": "printer"
        case "date & time": "clock"
        case "spotlight": "magnifyingglass"
        case "users & groups": "person.2"
        case "login items": "power"
        case "desktop & dock": "dock.rectangle"
        case "lock screen": "lock.display"
        case "wallpaper": "photo"
        default: "gearshape"
        }
    }

    private static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return raw as? [String: Any]
    }

    // MARK: - System commands

    /// The things a launcher is expected to be able to do to the machine itself.
    ///
    /// Every one is a fixed literal — nothing the user types is ever interpolated
    /// into a shell string — and every one is a local call. The destructive ones
    /// (restart, shut down, log out, empty trash) deliberately go through System
    /// Events, which shows the standard confirmation rather than acting silently.
    static func systemCommands() -> [CatalogItem] {
        [
            command(
                "sleep", "Sleep", "Put the Mac to sleep", symbol: "moon.zzz",
                aliases: ["suspend", "shut the lid"],
                action: .appleScript(#"tell application "System Events" to sleep"#)
            ),
            command(
                "displaysleep", "Sleep Display", "Turn the screen off without sleeping",
                symbol: "display.trianglebadge.exclamationmark",
                aliases: ["screen off", "monitor off", "turn off display"],
                action: .shell("/usr/bin/pmset displaysleepnow")
            ),
            command(
                "lock", "Lock Screen", "Lock the Mac and show the login window",
                symbol: "lock.display",
                aliases: ["lock the mac", "sign out screen", "secure"],
                action: .shell(
                    "'/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession' -suspend"
                )
            ),
            command(
                "screensaver", "Start Screen Saver", "Run the screen saver now",
                symbol: "sparkles.tv",
                aliases: ["screensaver", "idle"],
                action: .shell("/usr/bin/open -a ScreenSaverEngine")
            ),
            command(
                "restart", "Restart", "Restart the Mac", symbol: "arrow.clockwise.circle",
                aliases: ["reboot"],
                action: .appleScript(#"tell application "System Events" to restart"#)
            ),
            command(
                "shutdown", "Shut Down", "Shut the Mac down", symbol: "power",
                aliases: ["power off", "turn off"],
                action: .appleScript(#"tell application "System Events" to shut down"#)
            ),
            command(
                "logout", "Log Out", "Log the current user out", symbol: "rectangle.portrait.and.arrow.right",
                aliases: ["sign out"],
                action: .appleScript(#"tell application "System Events" to log out"#)
            ),
            command(
                "darkmode", "Toggle Dark Mode", "Switch between light and dark appearance",
                symbol: "circle.lefthalf.filled",
                aliases: ["dark mode", "light mode", "theme", "appearance"],
                action: .appleScript(
                    #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
                )
            ),
            command(
                "emptytrash", "Empty Trash", "Permanently delete everything in the Trash",
                symbol: "trash",
                aliases: ["delete trash", "bin", "clear trash"],
                action: .appleScript(#"tell application "Finder" to empty trash"#)
            ),
            command(
                "showhidden", "Show Hidden Files", "Reveal dotfiles in Finder",
                symbol: "eye",
                aliases: ["dotfiles", "hidden files", "reveal hidden"],
                action: .shell(
                    "/usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool true; /usr/bin/killall Finder"
                )
            ),
            command(
                "hidehidden", "Hide Hidden Files", "Stop showing dotfiles in Finder",
                symbol: "eye.slash",
                aliases: ["dotfiles", "hidden files"],
                action: .shell(
                    "/usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool false; /usr/bin/killall Finder"
                )
            ),
            command(
                "ejectall", "Eject All Disks", "Unmount every removable volume",
                symbol: "eject",
                aliases: ["unmount", "eject usb", "eject drive"],
                action: .appleScript(
                    #"tell application "Finder" to eject (every disk whose ejectable is true)"#
                )
            ),
            command(
                "screenshot", "Capture Selection", "Screenshot a region to the clipboard",
                symbol: "camera.viewfinder",
                aliases: ["screenshot", "screen capture", "grab", "snip"],
                action: .shell("/usr/sbin/screencapture -i -c")
            ),
            command(
                "screenshotfile", "Capture Selection to Desktop", "Screenshot a region to a file",
                symbol: "camera",
                aliases: ["screenshot", "screen capture", "save screenshot"],
                action: .shell("/usr/sbin/screencapture -i ~/Desktop/Screenshot-$(date +%Y%m%d-%H%M%S).png")
            ),
            command(
                "restartfinder", "Restart Finder", "Relaunch the Finder", symbol: "arrow.counterclockwise",
                aliases: ["relaunch finder", "kill finder"],
                action: .shell("/usr/bin/killall Finder")
            ),
            command(
                "restartdock", "Restart Dock", "Relaunch the Dock and Mission Control",
                symbol: "dock.rectangle",
                aliases: ["relaunch dock", "kill dock", "fix dock"],
                action: .shell("/usr/bin/killall Dock")
            ),
            command(
                "restartmenubar", "Restart Menu Bar", "Relaunch SystemUIServer and Control Center",
                symbol: "menubar.rectangle",
                aliases: ["fix menu bar", "control center", "status bar"],
                action: .shell("/usr/bin/killall SystemUIServer; /usr/bin/killall ControlCenter")
            ),
            command(
                "flushdns", "Flush DNS Cache", "Clear resolved hostnames", symbol: "arrow.triangle.2.circlepath",
                aliases: ["dns", "clear dns", "resolve"],
                action: .shell("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder")
            ),
            // Folders people reach for constantly; opening one is a Finder call.
            folder("home", "Home Folder", FileManager.default.homeDirectoryForCurrentUser.path,
                   aliases: ["~", "user folder"]),
            folder("downloads", "Downloads", NSHomeDirectory() + "/Downloads", aliases: ["dl"]),
            folder("documents", "Documents", NSHomeDirectory() + "/Documents", aliases: ["docs"]),
            folder("desktop", "Desktop", NSHomeDirectory() + "/Desktop"),
            folder("applications", "Applications Folder", "/Applications", aliases: ["apps"]),
            folder("trash", "Trash", NSHomeDirectory() + "/.Trash", aliases: ["bin", "deleted"]),
            folder("library", "Library", NSHomeDirectory() + "/Library",
                   aliases: ["app support", "caches", "preferences"]),
            folder("utilities", "Utilities", "/System/Applications/Utilities"),
        ]
    }

    private static func command(
        _ id: String, _ title: String, _ subtitle: String,
        symbol: String, aliases: [String] = [], action: CommandAction
    ) -> CatalogItem {
        CatalogItem(
            id: "cmd:" + id,
            title: title,
            subtitle: subtitle,
            category: .command,
            symbolName: symbol,
            keys: CatalogItem.keys(title: title, aliases: aliases),
            action: action
        )
    }

    private static func folder(
        _ id: String, _ title: String, _ path: String, aliases: [String] = []
    ) -> CatalogItem {
        CatalogItem(
            id: "folder:" + id,
            title: title,
            subtitle: abbreviate(path),
            category: .command,
            symbolName: "folder",
            keys: CatalogItem.keys(title: title, aliases: aliases + ["open folder"], weak: [path]),
            action: .openFile(path: path)
        )
    }

    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Crest's own tools

    /// Every panel section and every in-app action, so the app's own features are
    /// as findable as anything else. Before this, typing "clipboard" or "docker"
    /// into the command bar found nothing at all — the tools existed only behind
    /// the menu-bar panel, which is the opposite of what a command bar is for.
    static func tools() -> [CatalogItem] {
        var items = PanelSection.allCases.map { section in
            CatalogItem(
                id: "section:" + section.rawValue,
                title: section.rawValue,
                subtitle: "Open in the Crest panel",
                category: .tool,
                symbolName: section.iconName,
                keys: CatalogItem.keys(
                    title: section.rawValue,
                    aliases: sectionAliases[section] ?? [],
                    weak: ["crest", "panel"]
                ),
                action: .appAction("section:" + section.rawValue)
            )
        }

        items.append(contentsOf: actions.map { action in
            CatalogItem(
                id: action.id,
                title: action.title,
                subtitle: action.subtitle,
                category: .tool,
                symbolName: action.symbol,
                keys: CatalogItem.keys(
                    title: action.title,
                    aliases: action.aliases,
                    weak: ["crest"]
                ),
                action: .appAction(action.id)
            )
        })
        return items
    }

    private static let sectionAliases: [PanelSection: [String]] = [
        .system: ["cpu", "memory", "ram", "load", "metrics", "stats"],
        .disk: ["storage", "free space", "volume", "ssd"],
        .cleaner: ["junk", "caches", "clean up", "reclaim space"],
        .network: ["bandwidth", "speed", "upload", "download", "traffic"],
        .power: ["battery", "energy", "charge"],
        .tools: ["utilities", "extras"],
        .clipboard: ["copy history", "pasteboard", "clips", "paste"],
        .largeFolders: ["biggest folders", "space hogs", "disk usage", "du"],
        .docker: ["containers", "images", "volumes"],
        .homebrew: ["brew", "packages", "formulae", "casks"],
    ]

    struct Action: Sendable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let aliases: [String]
    }

    static let actions: [Action] = [
        Action(id: "action:scan", title: "Scan for Junk", subtitle: "Run the cleaner",
               symbol: "sparkles", aliases: ["clean", "cleanup", "free space", "caches"]),
        Action(id: "action:review", title: "Review Cleanable Items", subtitle: "Open the review window",
               symbol: "checklist", aliases: ["cleaner review", "what can i delete"]),
        Action(id: "action:keepawake", title: "Toggle Keep Awake", subtitle: "Prevent or allow sleep",
               symbol: "cup.and.saucer", aliases: ["caffeinate", "stay awake", "no sleep", "amphetamine"]),
        Action(id: "action:color", title: "Pick a Colour", subtitle: "Sample a colour from the screen",
               symbol: "eyedropper", aliases: ["color picker", "colour picker", "eyedropper", "hex"]),
        Action(id: "action:clipboard", title: "Clipboard History", subtitle: "Show recent copies",
               symbol: "doc.on.clipboard", aliases: ["paste history", "pasteboard", "clips"]),
        Action(id: "action:uninstall", title: "Uninstall an App", subtitle: "Remove an app and its leftovers",
               symbol: "trash.slash", aliases: ["remove app", "delete app", "app cleaner"]),
        Action(id: "action:network", title: "Network Activity", subtitle: "Live speed and which apps use it",
               symbol: "network", aliases: ["bandwidth", "who is using my internet", "speed"]),
        Action(id: "action:brewupdate", title: "Update Homebrew Packages", subtitle: "Runs brew upgrade",
               symbol: "arrow.up.circle", aliases: ["brew upgrade", "update brew", "outdated"]),
        Action(id: "action:brewcleanup", title: "Reclaim Homebrew Space", subtitle: "Runs brew cleanup",
               symbol: "cup.and.saucer.fill", aliases: ["brew cleanup", "prune brew"]),
        Action(id: "action:reindex", title: "Rebuild Search Index", subtitle: "Rescan apps, settings and tools",
               symbol: "arrow.clockwise", aliases: ["reindex", "refresh index", "rescan apps"]),
        Action(id: "action:settings", title: "Crest Settings", subtitle: "Open Crest's own preferences",
               symbol: "gearshape", aliases: ["preferences", "configure"]),
        Action(id: "action:shortcuts", title: "Edit Shortcuts and Aliases", subtitle: "Assign a key or a name to any app",
               symbol: "command", aliases: ["hotkey", "keyboard shortcut", "alias", "rename", "bind"]),
        Action(id: "action:checkupdates", title: "Check for Updates", subtitle: "See whether a newer Crest exists",
               symbol: "arrow.down.circle", aliases: ["update", "upgrade", "new version"]),
        Action(id: "action:onboarding", title: "Show the Welcome Guide", subtitle: "Replay the first-run setup",
               symbol: "sparkles.rectangle.stack", aliases: ["onboarding", "getting started", "tour", "welcome"]),
        Action(id: "action:dictate", title: "Start Dictating", subtitle: "Talk and have the text typed for you",
               symbol: "mic", aliases: ["dictation", "voice", "speech to text", "transcribe", "talk", "wispr"]),
        Action(id: "action:meeting", title: "Record Meeting Notes", subtitle: "Transcribe the call and summarize it on-device",
               symbol: "text.bubble", aliases: ["meeting", "notetaker", "take notes", "record call", "minutes"]),
        Action(id: "action:meetingnotes", title: "Meeting Notes", subtitle: "Read past meetings and their summaries",
               symbol: "list.bullet.rectangle", aliases: ["past meetings", "transcripts", "summaries", "notes"]),
        Action(id: "action:lastdictation", title: "Copy Last Dictation", subtitle: "Put the last thing you dictated back on the clipboard",
               symbol: "doc.on.doc", aliases: ["last transcript", "redo dictation", "what did i say"]),
        Action(id: "action:vocabulary", title: "Edit Voice Vocabulary", subtitle: "Teach the recognizer names and jargon",
               symbol: "character.book.closed", aliases: ["dictionary", "vocabulary", "custom words", "spelling"]),
    ]
}
