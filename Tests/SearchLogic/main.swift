import Foundation

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print(condition ? "  ok   \(label)" : "  FAIL \(label)")
    if !condition { failures += 1 }
}

let home = NSHomeDirectory()
func at(_ relative: String) -> String { "\(home)/\(relative)" }

func rank(_ relative: String, _ query: String, folder: Bool = false, used: Date? = nil) -> Int? {
    FileRanking.score(
        FileRanking.Candidate(
            path: at(relative),
            name: (relative as NSString).lastPathComponent,
            isFolder: folder,
            lastUsed: used
        ),
        query: query,
        // Fixed, so a recency bonus cannot make a test pass on Monday and fail on
        // Friday.
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

print("folders are findable at all")
// The whole complaint: a search for "desk" used to return `~/Desktop` and five
// object files out of a build directory, because Spotlight sorts by a last-used
// date that almost nothing carries and the first six results were taken as-is.
check("the home folder wins its own name", rank("Desktop", "desk", folder: true)! > 1000)
check("a folder outranks a file matching the same way",
      rank("Desktop", "desk", folder: true)! > rank("Desktop", "desk", folder: false)!)
check("a folder outranks a deeper file that merely contains the word",
      rank("Downloads", "down", folder: true)!
          > rank("Developer/app/components/FormDropDown.jsx", "down")!)

print("build output never appears")
for path in [
    "Desktop/app/node_modules/react/index.js",
    "Desktop/app/src-tauri/target/debug/deps/lib.rcgu.o",
    "Desktop/app/src-tauri/target/debug/incremental/lib-28txt/x.bin",
    "Library/Developer/Xcode/DerivedData/Crest-abc/Build/Products/Debug/Crest",
    "Developer/api/__pycache__/views.cpython-311.pyc",
    "Developer/ios/Pods/Alamofire/Source/Alamofire.swift",
    "Developer/web/.next/static/chunks/main.js",
    "Library/Caches/com.apple.Safari/thing.db",
    "Desktop/project/build/intermediates.noindex/x.txt",
    "Movies/CapCut/User Data/Cache/music",
] {
    check("dropped: \(path)", rank(path, "x") == nil)
}

print("but the folders those live in are not")
// `target` and `build` are ordinary words. Excluding them outright would hide
// real work, so only the unambiguous pairs are dropped.
check("a folder called target survives", rank("Desktop/archery/target", "target", folder: true) != nil)
check("a folder called build survives", rank("Desktop/house/build", "build", folder: true) != nil)
check("a folder called vendor does not", rank("Desktop/shop/vendor", "vendor", folder: true) == nil)

print("name match beats coincidence")
check("an exact name beats a prefix",
      FileRanking.nameScore("desk", query: "desk") > FileRanking.nameScore("desktop", query: "desk"))
check("a prefix beats a word inside the name",
      FileRanking.nameScore("desktop", query: "desk") > FileRanking.nameScore("lamp-desk", query: "desk"))
// A separator is what makes something a word, so "lamp-desk" and
// "wolfcut_desktop_lib" both match at the word tier and tie here — depth and
// folder-ness are what separate those two, not the name. The tier below is for a
// query that lands in the middle of a word and matches nothing in particular.
check("a word inside the name beats a bare substring",
      FileRanking.nameScore("lamp-desk", query: "desk") > FileRanking.nameScore("wolfcutdesktoplib", query: "desk"))
check("two word-boundary matches tie on name alone",
      FileRanking.nameScore("lamp-desk", query: "desk") == FileRanking.nameScore("wolfcut_desktop_lib", query: "desk"))
check("case does not matter", FileRanking.nameScore("Desktop", query: "DESK") == FileRanking.nameScore("desktop", query: "desk"))
check("the extension does not hide an exact name",
      FileRanking.nameScore("notes.txt", query: "notes") > FileRanking.nameScore("my-notes.txt", query: "notes"))

print("shallow beats deep")
check("a folder under home beats the same name three levels down",
      rank("Documents", "doc", folder: true)! > rank("Developer/shapy/docs", "doc", folder: true)!)
check("depth alone cannot beat a better name",
      rank("Documents", "documents", folder: true)!
          > rank("Documents/a/b/c/d/e/f/documents", "documents", folder: true)!)
check("but a perfect deep match still beats a weak shallow one",
      rank("Developer/x/y/z/reports", "reports", folder: true)!
          > rank("Desktop/quarterly-reports-archive", "reports", folder: true)!)

print("Library is machinery")
// It is not excluded — application data lives there and is occasionally wanted —
// but it must never take a slot from something in the user's own files.
check("an app support folder loses to a real one",
      rank("Desktop/Crest", "crest", folder: true)!
          > rank("Library/Application Support/Crest", "crest", folder: true)!)
check("and loses even when the real one is deeper",
      rank("Developer/a/b/Crest", "crest", folder: true)!
          > rank("Library/Application Support/Crest", "crest", folder: true)!)

print("recency breaks ties")
let recent = Date(timeIntervalSince1970: 1_800_000_000 - 86_400)
let old = Date(timeIntervalSince1970: 1_000_000_000)
check("something opened yesterday outranks the same thing untouched",
      rank("Desktop/notes", "notes", folder: true, used: recent)!
          > rank("Desktop/notes", "notes", folder: true, used: old)!)
check("recency cannot rescue a worse name",
      rank("Desktop/notes", "notes", folder: true)!
          > rank("Desktop/scratch-notes-old", "notes", folder: true, used: recent)!)

print("packages are documents, not places")
for name in ["Crest.xcodeproj", "Photos Library.photoslibrary", "Crest.app", "Notes.rtfd"] {
    check("\(name) is a package", FileRanking.isPackage(name: name))
}
check("an ordinary folder is not", !FileRanking.isPackage(name: "Documents"))
check("a folder with a dot in its name is not", !FileRanking.isPackage(name: "v1.2.3"))

print("the cheap pass agrees with the expensive one")
// `provisionalScore` picks the shortlist from paths alone, and only the survivors
// are looked up on disk. If it disagreed with the final score about what is worth
// keeping, the shortlist would throw away results the ranking would have wanted.
for path in ["Desktop", "Documents/reports", "Library/Caches/x", "Desktop/app/node_modules/x.js"] {
    let provisional = FileRanking.provisionalScore(path: at(path), query: "reports")
    let final = rank(path, "reports")
    check("both agree whether to keep \(path)", (provisional == nil) == (final == nil))
}

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
