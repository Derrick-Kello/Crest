//
//  UpdateService.swift
//  Crest
//

import Foundation
import OSLog

/// Checks whether a newer Crest has been released.
///
/// Reads the GitHub releases API directly rather than shipping a Sparkle feed:
/// releases are already published there, the endpoint needs no key for a public
/// repository, and it means there is no second place to remember to update when
/// a version goes out. The check only ever reads — Crest never downloads or
/// replaces itself, so an update is a link the user follows deliberately.
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// The repository exists but has published no releases. Distinct from a
        /// failure: nothing is wrong, there is just nothing newer to point at, and
        /// saying "couldn't reach GitHub" for it sends people to check their Wi-Fi.
        case noReleases
        case available(version: String, url: URL, notes: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    /// What this build calls itself, for the About pane and the comparison.
    let currentVersion = Bundle.main.shortVersion
    let buildNumber = Bundle.main.buildNumber

    private let endpoint = URL(string: "https://api.github.com/repos/Derrick-Kello/Crest/releases/latest")!
    private let logger = Logger(subsystem: "com.smarthive.crest", category: "Updates")
    private var task: Task<Void, Never>?

    private init() {
        lastChecked = Preferences.lastUpdateCheck
    }

    var isChecking: Bool { state == .checking }

    /// The release waiting to be installed, if the last check found one. Read by
    /// the menu-bar icon and the panel, which both want to point at it without
    /// pulling the whole state apart.
    var pending: (version: String, url: URL)? {
        guard case .available(let version, let url, _) = state else { return nil }
        return (version, url)
    }

    /// Runs a check. A check already in flight is left alone rather than
    /// restarted, so a double-click does not fire two requests.
    ///
    /// `announcing` decides whether finding a release raises a notification. Off
    /// for a check the user asked for: they are already looking at the answer, and
    /// a banner over the pane that just told them the same thing is noise.
    func check(announcing: Bool = false) {
        guard !isChecking else { return }
        announcesResult = announcing
        state = .checking
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await self.fetchLatest()
                guard !Task.isCancelled else { return }
                self.apply(release)
            } catch UpdateError.noReleases {
                guard !Task.isCancelled else { return }
                self.announcesResult = false
                self.lastChecked = Date()
                Preferences.lastUpdateCheck = self.lastChecked
                self.state = .noReleases
            } catch {
                guard !Task.isCancelled else { return }
                self.announcesResult = false
                self.logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed("Couldn't reach GitHub. Check your connection and try again.")
            }
        }
    }

    /// The once-a-day background check, and the only one that speaks up. Silent
    /// about failure: a laptop that opened its lid without a network should not
    /// greet the user with an error.
    func checkInBackgroundIfDue() {
        guard Preferences.automaticUpdateChecks else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 86_400 { return }
        check(announcing: true)
    }

    /// Whether the check in flight should speak up if it finds something.
    private var announcesResult = false

    private func apply(_ release: Release) {
        let announces = announcesResult
        announcesResult = false

        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        lastChecked = Date()
        Preferences.lastUpdateCheck = lastChecked

        guard Self.isNewer(latest, than: currentVersion) else {
            state = .upToDate
            return
        }
        guard let url = URL(string: release.htmlURL) else {
            state = .upToDate
            return
        }
        state = .available(version: latest, url: url, notes: Self.summarize(release.body))

        guard announces else { return }
        let notes = Self.summarize(release.body)
        Task { await UpdateNotifier.shared.announce(version: latest, url: url, notes: notes) }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Crest/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        // The answer changes at most once per release, and a stale one for a few
        // minutes is harmless; a cached hit costs nothing at all.
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        // GitHub answers 404 for a repository with no published releases, which is
        // the state a project is in before its first tag rather than an error.
        if http.statusCode == 404 { throw UpdateError.noReleases }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.badResponse }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Version comparison

    /// Compares dotted version numbers component by component.
    ///
    /// A plain string comparison gets "1.10" wrong against "1.9", which is exactly
    /// the release where a wrong answer would be least noticed and most annoying.
    /// Anything non-numeric in a component reads as zero rather than throwing, so
    /// a "1.2.0-beta" tag degrades to 1.2.0 instead of failing the whole check.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(of: candidate)
        let right = components(of: current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    /// Release notes shown inline are a teaser, not the changelog — the full one
    /// is a click away on the release page.
    private static func summarize(_ body: String?) -> String {
        guard let body else { return "" }
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.prefix(4).joined(separator: "\n")
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }

    private enum UpdateError: Error {
        case badResponse
        case noReleases
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
