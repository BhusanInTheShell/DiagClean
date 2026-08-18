import Foundation
import Testing
@testable import DiagCleanKit

/// Builds a synthetic home directory under a temp folder so the real targets can be
/// pointed at a known layout. These tests are about *what gets offered* — the most
/// consequential decision in Clean, because anything offered is something a technician
/// may reasonably accept without inspecting it individually.
@Suite("Clean targets")
struct CleanTargetTests {

    // MARK: - Temporary files

    @Test("offers temp entries that have been untouched for a day")
    func offersStaleTempEntries() throws {
        let workspace = try TempWorkspace()
        let temp = try workspace.makeDirectory("T")
        let stale = try workspace.makeFile("T/old.bin", modified: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60))

        let target = TemporaryFilesTarget(tempRoot: temp, protectedPaths: [])

        #expect(target.candidates().map(\.path) == [stale])
    }

    /// A temp file written minutes ago almost certainly belongs to something running
    /// right now. The bytes are not worth the risk of pulling it out from under a
    /// running app on somebody else's machine.
    @Test("leaves recently-touched temp entries alone")
    func skipsFreshTempEntries() throws {
        let workspace = try TempWorkspace()
        let temp = try workspace.makeDirectory("T")
        try workspace.makeFile("T/in-use.sock", modified: Date())

        let target = TemporaryFilesTarget(tempRoot: temp, protectedPaths: [])

        #expect(target.candidates().isEmpty)
    }

    @Test("skips a temp entry whose age cannot be established")
    func skipsUndatableTempEntries() throws {
        let workspace = try TempWorkspace()
        let temp = try workspace.makeDirectory("T")
        try workspace.makeFile("T/thing.bin", modified: Date(timeIntervalSinceNow: -10 * 24 * 60 * 60))

        // A candidate that no longer exists by the time its date is read has no
        // readable timestamp, which must mean "leave it" rather than "assume stale".
        let target = TemporaryFilesTarget(
            tempRoot: temp,
            protectedPaths: [],
            minimumAge: 24 * 60 * 60,
            now: { Date(timeIntervalSinceNow: -365 * 24 * 60 * 60) }
        )

        #expect(target.candidates().isEmpty, "nothing is old enough relative to a cutoff in the past")
    }

    @Test("its guard permits only the temp root")
    func temporaryGuardIsNarrow() throws {
        let workspace = try TempWorkspace()
        let temp = try workspace.makeDirectory("T")
        let elsewhere = try workspace.makeDirectory("elsewhere", "thing")

        let target = TemporaryFilesTarget(tempRoot: temp, protectedPaths: [])

        #expect(target.pathGuard.decide(elsewhere).denial == .outsideAllowedRoots)
    }

    // MARK: - Browser caches

    @Test("finds Chromium caches in both the Caches and Application Support trees")
    func findsChromiumCachesInBothTrees() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/data")
        try workspace.makeFile("home/Library/Caches/BraveSoftware/Brave-Browser/Default/Code Cache/data")
        try workspace.makeFile("home/Library/Application Support/BraveSoftware/Brave-Browser/ShaderCache/data")
        try workspace.makeFile("home/Library/Application Support/BraveSoftware/Brave-Browser/Default/GPUCache/data")

        let target = BrowserCachesTarget(user: user, protectedPaths: [])
        let names = target.candidates().map { ($0.path as NSString).lastPathComponent }.sorted()

        #expect(names == ["Cache", "Code Cache", "GPUCache", "ShaderCache"])
        #expect(target.candidates().allSatisfy { $0.ownerLabel == "Brave Browser" })
    }

    /// The single most important thing this target does is *not* offer the things next
    /// to the caches. Losing a browser cache costs a few seconds; losing cookies logs
    /// somebody out of everything they use.
    @Test("never offers cookies, history, passwords or extensions")
    func neverOffersBrowserData() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        let profile = "home/Library/Application Support/Google/Chrome/Default"
        try workspace.makeFile("\(profile)/Cache/data")
        try workspace.makeFile("\(profile)/Cookies")
        try workspace.makeFile("\(profile)/History")
        try workspace.makeFile("\(profile)/Login Data")
        try workspace.makeFile("\(profile)/Bookmarks")
        try workspace.makeDirectory("home", "Library", "Application Support", "Google", "Chrome", "Default", "Extensions")

        let target = BrowserCachesTarget(user: user, protectedPaths: [])
        let offered = target.candidates().map { ($0.path as NSString).lastPathComponent }

        for forbidden in ["Cookies", "History", "Login Data", "Bookmarks", "Extensions"] {
            #expect(!offered.contains(forbidden), "\(forbidden) must never be a clean candidate")
        }
    }

    @Test("ignores directories that are not Chromium profiles")
    func ignoresNonProfileDirectories() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Caches/Google/Chrome/Default/Cache/data")
        try workspace.makeFile("home/Library/Caches/Google/Chrome/Profile 2/Cache/data")
        // Not a profile: a same-named directory somewhere Chromium keeps other state.
        try workspace.makeFile("home/Library/Caches/Google/Chrome/BrowserMetrics/Cache/data")

        let target = BrowserCachesTarget(user: user, protectedPaths: [])
        let parents = target.candidates().map { (($0.path as NSString).deletingLastPathComponent as NSString).lastPathComponent }.sorted()

        #expect(parents == ["Default", "Profile 2"])
    }

    @Test("finds the Firefox disk cache inside each randomly-named profile")
    func findsFirefoxCaches() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Caches/Firefox/Profiles/a1b2c3.default/cache2/data")
        try workspace.makeFile("home/Library/Caches/Firefox/Profiles/x9y8z7.dev/cache2/data")

        let target = BrowserCachesTarget(user: user, protectedPaths: [])

        #expect(target.candidates().count == 2)
        #expect(target.candidates().allSatisfy { $0.ownerLabel == "Firefox" })
    }

    @Test("its guard permits only recognised browser directories, not the Caches root")
    func browserGuardIsNarrow() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        try workspace.makeDirectory("home", "Library", "Caches", "Google", "Chrome")
        let unrelated = try workspace.makeDirectory("home", "Library", "Caches", "com.example.notabrowser")

        let target = BrowserCachesTarget(user: user, protectedPaths: [])

        #expect(target.pathGuard.decide(unrelated).denial == .outsideAllowedRoots)
    }

    // MARK: - Application caches

    @Test("offers each top-level cache directory as its own item")
    func offersTopLevelCaches() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Caches/com.example.editor/blob")
        try workspace.makeFile("home/Library/Caches/Homebrew/blob")

        let target = ApplicationCachesTarget(user: user, protectedPaths: [])
        let names = target.candidates().map { ($0.path as NSString).lastPathComponent }.sorted()

        #expect(names == ["Homebrew", "com.example.editor"])
    }

    @Test("excludes directories the browser target already covers, so bytes are never counted twice")
    func excludesBrowserOwnedDirectories() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/data")
        try workspace.makeFile("home/Library/Caches/Google/Chrome/Default/Cache/data")
        try workspace.makeFile("home/Library/Caches/Firefox/Profiles/abc/cache2/data")
        try workspace.makeFile("home/Library/Caches/com.apple.Safari/blob")
        try workspace.makeFile("home/Library/Caches/com.example.editor/blob")

        let target = ApplicationCachesTarget(user: user, protectedPaths: [])
        let names = target.candidates().map { ($0.path as NSString).lastPathComponent }

        #expect(names == ["com.example.editor"])
    }

    @Test("declines CloudKit, where the rebuild costs a full re-download")
    func excludesCloudKit() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        try workspace.makeFile("home/Library/Caches/CloudKit/blob")

        let target = ApplicationCachesTarget(user: user, protectedPaths: [])

        #expect(target.candidates().isEmpty)
    }

    @Test("shortens bundle identifiers into something a person can act on")
    func friendlyNames() {
        #expect(ApplicationCachesTarget.friendlyName(for: "com.apple.Spotlight") == "Spotlight")
        #expect(ApplicationCachesTarget.friendlyName(for: "com.example.editor.helper") == "editor.helper")
        #expect(ApplicationCachesTarget.friendlyName(for: "Homebrew") == "Homebrew")
        #expect(ApplicationCachesTarget.friendlyName(for: "go-build") == "go-build")
    }

    // MARK: - The default target set as a whole

    /// The protected list is the last line of defence, so its coverage of the obvious
    /// personal directories is worth asserting directly rather than trusting by
    /// inspection.
    @Test("the built-in protected list covers the directories that hold real work")
    func protectedListCoversPersonalDirectories() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        let protected = ProtectedPaths.forClean(for: user)

        for name in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"] {
            #expect(protected.contains(user.inHome(name)), "\(name) must be protected")
        }
        #expect(protected.contains(user.inHome("Library", "Mobile Documents")), "iCloud Drive must be protected")
        #expect(protected.contains(user.inHome("Library", "Keychains")), "keychains must be protected")
        #expect(protected.contains(user.appSupportDirectory), "DiagClean's own audit trail must be protected")
    }

    @Test("no default target will touch a protected directory even if one appears inside its root")
    func defaultTargetsRespectProtectedPaths() throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        // DiagClean's own log directory lives inside Application Support, and is
        // protected; nothing may offer it.
        let logs = try workspace.makeDirectory("home", "Library", "Application Support", "DiagClean", "logs")

        for target in CleanScanner.defaultTargets(user: user) {
            #expect(!target.pathGuard.decide(logs).isAllowed, "\(target.category) must refuse the audit trail")
        }
    }
}
