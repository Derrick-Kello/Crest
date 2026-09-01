//
//  FolderIndex.swift
//  Crest
//

import Foundation

/// Puts the user's folders in the catalog, next to their apps.
///
/// The catalog indexed applications, System Settings panes, system commands and
/// Crest's own tools — everything except the places you keep your work. Folders
/// were reachable only through Spotlight, which meant they arrived a beat late,
/// were capped at six rows shared with every matching file, and vanished
/// entirely with file search turned off. Typing "downloads" found nothing.
///
/// This is the other half of the answer: a small, bounded, local index of the
/// folders someone actually navigates to, scanned once at launch alongside the
/// apps, matched by the same fuzzy matcher, and answered instantly and offline.
/// It is not a filesystem crawl and is not trying to be — Spotlight already
/// covers the long tail, and this covers the part that has to be immediate.
nonisolated enum FolderIndex {

    /// How deep to go under the folders people keep projects in.
    ///
    /// Two levels below home, so `~/Desktop/wolfcut` is indexed and
    /// `~/Desktop/wolfcut/WolfCut` is not. Three levels was tried on a real home
    /// directory and produced several thousand entries, most of them a checkout's
    /// internal structure — which is what Spotlight is for.
    private static let maximumDepth = 2

    /// A ceiling on the whole index, so an unusual home directory costs a bounded
    /// amount of memory and a bounded amount of scan time rather than whatever it
    /// happens to contain.
    private static let limit = 1200

    /// The folders worth descending into. Everything directly under home is
    /// indexed whatever it is called; only these get a second level, because they
    /// are where projects live and the rest are where applications keep things.
    private static let workRoots: Set<String> = [
        "Desktop", "Documents", "Downloads", "Developer", "Projects", "Code",
        "Sites", "Movies", "Music", "Pictures", "Public", "src", "work", "repos",
    ]

    static func scan() -> [CatalogItem] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path

        var items: [CatalogItem] = [homeItem(path: home)]
        var queue: [(path: String, depth: Int)] = [(home, 0)]

        // Breadth first, so the shallow folders — the ones somebody is most
        // likely to be looking for — are the ones that survive the cap.
        while !queue.isEmpty, items.count < limit {
            let (path, depth) = queue.removeFirst()

            guard let names = try? manager.contentsOfDirectory(atPath: path) else { continue }

            for name in names.sorted() {
                guard items.count < limit else { break }
                guard !name.hasPrefix("."), !FileRanking.isPackage(name: name) else { continue }

                let child = path + "/" + name
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: child, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      !FileRanking.isNoise(path: child)
                else { continue }

                items.append(item(path: child, name: name, home: home))

                // Descend only under the folders people keep work in, and only
                // while the depth budget lasts.
                let root = depth == 0 ? name : rootName(of: child, home: home)
                if depth + 1 < maximumDepth, let root, workRoots.contains(root) {
                    queue.append((child, depth + 1))
                }
            }
        }

        return items
    }

    // MARK: - Items

    private static func homeItem(path: String) -> CatalogItem {
        CatalogItem(
            id: "folder:" + path,
            title: "Home",
            subtitle: "~",
            category: .file,
            iconPath: path,
            symbolName: "house",
            keys: CatalogItem.keys(
                title: "Home",
                aliases: [(path as NSString).lastPathComponent, "~"],
                weak: ["folder", "home folder"]
            ),
            action: .openFile(path: path)
        )
    }

    private static func item(path: String, name: String, home: String) -> CatalogItem {
        let parent = (path as NSString).deletingLastPathComponent
        return CatalogItem(
            id: "folder:" + path,
            title: name,
            subtitle: abbreviate(parent, home: home),
            category: .file,
            iconPath: path,
            symbolName: "folder",
            // "folder" as a weak key so that typing the word alone lists them,
            // which is how somebody finds out the bar knows about folders at all.
            keys: CatalogItem.keys(title: name, weak: ["folder", "directory"]),
            action: .openFile(path: path)
        )
    }

    // MARK: - Paths

    /// The name of the folder directly under home that this path sits in.
    private static func rootName(of path: String, home: String) -> String? {
        guard path.hasPrefix(home + "/") else { return nil }
        return String(path.dropFirst(home.count + 1)).split(separator: "/").first.map(String.init)
    }

    private static func abbreviate(_ path: String, home: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
