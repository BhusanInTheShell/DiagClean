import Foundation

/// The safety net for Analyze, which is the one feature that can reach anywhere on the
/// disk rather than into a fixed set of known-safe locations.
///
/// The CLI's position is that there is no allowed-roots list Analyze could sensibly
/// check against, since browsing anywhere is the entire point, so its only protection is
/// procedural: one item at a time, full path shown, typed confirmation. That reasoning is
/// right about *browsing* and gives up too early on *removal*. Browsing is read-only and
/// harmless; removing is neither, and a disk browser has no business trashing `/System`
/// or somebody's home folder no matter how carefully it asks first.
///
/// So this inverts the usual shape. Clean and Uninstall use a narrow allowlist, because
/// they know exactly where they belong. Analyze uses a denylist plus a sensitivity tier,
/// because it genuinely might belong anywhere — but a short list of things should never
/// be removable from a disk browser, and a second list should be removable only after
/// somebody has been told plainly what they are looking at.
public struct AnalyzeGuard: Sendable {
    private let user: UserPaths
    private let resolver: PathResolving

    /// System locations. Trashing any of these breaks the machine, and none of them is
    /// ever the answer to "the disk is full".
    private static let systemRoots = [
        "/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/private/var/db",
        "/Library", "/cores", "/opt",
    ]

    /// Every root is canonicalised through `realpath` on construction.
    ///
    /// This is not incidental tidying. `PathGuard.standardize` is lexical, and on macOS
    /// `URL.standardizedFileURL` also strips a leading `/private` — so a temp directory
    /// standardises to `/var/folders/…` while the very same directory resolved through
    /// `realpath` comes back as `/private/var/folders/…`. Comparing one form against the
    /// other silently never matches, and a guard that silently never matches is a guard
    /// that allows everything. `PathGuard` canonicalises both sides for exactly this
    /// reason; so does this.
    public init(user: UserPaths = .current(), resolver: PathResolving = LivePathResolver()) {
        self.user = user
        self.resolver = resolver
    }

    private func canonicalRoot(_ path: String) -> String {
        PathGuard.canonicalize(path, using: resolver)
    }

    /// The personal folders themselves cannot go, but their contents can. Finding a
    /// forgotten 40 GB export in Movies is a real reason to use this tool; losing the
    /// Movies folder entirely is not something anybody meant to do.
    private var personalFolders: [String] {
        ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public"]
    }

    /// Not personal data, but just as fatal to lose wholesale. `~/Library` holds every
    /// app's preferences, containers and keychains — the system-wide `/Library` is
    /// already covered as a system path, and its per-user twin deserves the same
    /// treatment. Contents stay reachable: clearing `~/Library/Caches/something` is a
    /// perfectly ordinary thing to do from here.
    private var essentialHomeFolders: [String] {
        ["Library", "Applications"]
    }

    public func decide(_ path: String) -> AnalyzeDecision {
        let standardized = PathGuard.standardize(path)

        guard !resolver.isSymbolicLink(at: standardized) else {
            return .denied(.symbolicLink)
        }

        let parent = (standardized as NSString).deletingLastPathComponent
        let leaf = (standardized as NSString).lastPathComponent
        guard let resolvedParent = resolver.realPath(of: parent) else {
            return .denied(.doesNotExist)
        }
        let canonical = (resolvedParent as NSString).appendingPathComponent(leaf)

        if isVolumeRoot(canonical) {
            return .denied(.volumeRoot)
        }
        if PathGuard.pathsEqual(canonical, canonicalRoot(user.home)) {
            return .denied(.homeFolder)
        }
        if let root = Self.systemRoots.first(where: { PathGuard.isSameOrDescendant(canonical, of: $0) }) {
            return .denied(.systemPath(root))
        }

        // Applications are Uninstall's job. Trashing a bundle from here would leave its
        // caches, preferences and containers behind, which is exactly the mess Uninstall
        // exists to prevent.
        if canonical.hasSuffix(".app"),
           PathGuard.isSameOrDescendant(canonical, of: "/Applications")
            || PathGuard.isSameOrDescendant(canonical, of: canonicalRoot(user.inHome("Applications"))) {
            return .denied(.applicationBundle(leaf))
        }

        for name in essentialHomeFolders where PathGuard.pathsEqual(canonical, canonicalRoot(user.inHome(name))) {
            return .denied(.essentialFolderItself(name))
        }
        for name in personalFolders where PathGuard.pathsEqual(canonical, canonicalRoot(user.inHome(name))) {
            return .denied(.personalFolderItself(name))
        }
        for credential in [user.inHome("Library", "Keychains"), user.inHome(".ssh"), user.inHome(".gnupg")]
        where PathGuard.isSameOrDescendant(canonical, of: canonicalRoot(credential)) {
            return .denied(.credentials)
        }
        if PathGuard.isSameOrDescendant(canonical, of: canonicalRoot(user.appSupportDirectory)) {
            return .denied(.auditTrail)
        }

        return .allowed(canonicalPath: canonical, sensitivity: sensitivity(of: canonical))
    }

    private func sensitivity(of canonical: String) -> RemovalSensitivity {
        for name in personalFolders
        where PathGuard.isSameOrDescendant(canonical, of: canonicalRoot(user.inHome(name))) {
            return .personal(container: name)
        }
        for (path, label) in [
            (user.inHome("Library", "Mobile Documents"), "iCloud Drive"),
            (user.inHome("Library", "CloudStorage"), "cloud storage"),
        ] where PathGuard.isSameOrDescendant(canonical, of: canonicalRoot(path)) {
            // Worse than a local mistake: a synced file deleted here disappears from
            // every device the account touches.
            return .personal(container: label)
        }
        return .normal
    }

    private func isVolumeRoot(_ canonical: String) -> Bool {
        if canonical == "/" { return true }
        // /Volumes/Something, but not /Volumes/Something/inside.
        let parts = canonical.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count == 2 && parts[0] == "Volumes"
    }
}
