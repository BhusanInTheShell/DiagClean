import Foundation

/// The top-level entries of `~/Library/Caches`, one per app.
///
/// Apple's own convention is that anything here is disposable and apps must regenerate
/// it on demand, which is what makes a single general sweep defensible where a sweep of
/// `~/Library` would not be. Entries already covered by `BrowserCachesTarget` are
/// excluded so the same bytes are never offered — or counted — twice.
///
/// Each top-level entry is its own item rather than the whole directory being one
/// blob, so the review list reads as a list of applications with sizes instead of a
/// single unexaminable "1.4 GB" the technician has to take on faith.
public struct ApplicationCachesTarget: CleanTarget {
    public let category = CleanCategory.applicationCaches
    public let pathGuard: PathGuard

    private let cachesRoot: String
    private let excludedNames: Set<String>

    /// Entries this target declines even though they are technically caches.
    ///
    /// `CloudKit` is the notable one: clearing it is safe in the sense that nothing is
    /// lost, and expensive in the sense that every CloudKit-backed app re-downloads its
    /// state afterwards. On a metered connection or a slow office link that is a worse
    /// afternoon than the space was worth.
    public static let conservativeExclusions: Set<String> = [
        "CloudKit",
    ]

    public init(
        user: UserPaths,
        protectedPaths: [String],
        browsers: [BrowserCachesTarget.ChromiumBrowser] = BrowserCachesTarget.knownChromiumBrowsers,
        resolver: PathResolving = LivePathResolver()
    ) {
        self.cachesRoot = user.caches

        // A Chromium vendor directory's first path component is what appears at the top
        // level of ~/Library/Caches — "BraveSoftware" for "BraveSoftware/Brave-Browser".
        var excluded = Set(browsers.compactMap { $0.relativePath.split(separator: "/").first.map(String.init) })
        excluded.insert("Firefox")
        excluded.insert("com.apple.Safari")
        excluded.formUnion(Self.conservativeExclusions)
        self.excludedNames = excluded

        self.pathGuard = PathGuard(
            allowedRoots: [user.caches],
            protectedPaths: protectedPaths,
            resolver: resolver
        )
    }

    public func candidates() -> [Candidate] {
        FileSystemListing.children(of: cachesRoot)
            .filter { !excludedNames.contains(($0 as NSString).lastPathComponent) }
            .map { Candidate(path: $0, ownerLabel: Self.friendlyName(for: ($0 as NSString).lastPathComponent)) }
    }

    /// Cache directories are named by bundle identifier. `com.apple.Spotlight` reads as
    /// noise in a list; `Spotlight` reads as something a person can make a decision
    /// about. The full path is always shown alongside, so nothing is hidden by this.
    static func friendlyName(for directoryName: String) -> String {
        let parts = directoryName.split(separator: ".")
        guard parts.count >= 3, parts[0] == "com" || parts[0] == "org" || parts[0] == "io" else {
            return directoryName
        }
        return parts.dropFirst(2).joined(separator: ".")
    }
}
