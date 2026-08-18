import Foundation

/// Finds the files an app leaves behind, measured and guard-checked.
///
/// Read-only from start to finish, like `CleanScanner` — which is what makes it safe to
/// run the moment somebody selects an app, rather than behind another button press.
///
/// Only the immediate children of each Library root are examined, never a recursive
/// walk. Roots like `~/Library/Caches` hold one directory per app, so descending would
/// be both slow and wrong: it would match files *inside* an unrelated app's folder
/// because their names happen to mention this one.
public struct LeftoverScanner: Sendable {
    /// The per-user Library directories an app actually scatters into. Scoped to the
    /// user's own Library: `/Library` and `/Library/LaunchDaemons` are root-owned and
    /// shared between accounts, and the overwhelming majority of an app's footprint is
    /// here anyway.
    public static let defaultLocations = [
        "Application Support",
        "Caches",
        "Preferences",
        "Logs",
        "Saved Application State",
        "WebKit",
        "HTTPStorages",
        "Containers",
        "Group Containers",
        "LaunchAgents",
    ]

    public let pathGuard: PathGuard
    private let library: String
    private let locations: [String]
    private let sizer: DirectorySizer

    public init(
        user: UserPaths = .current(),
        locations: [String] = LeftoverScanner.defaultLocations,
        extraProtectedPaths: [String] = [],
        sizer: DirectorySizer = DirectorySizer(),
        resolver: PathResolving = LivePathResolver()
    ) {
        self.library = user.library
        self.locations = locations
        self.sizer = sizer

        let roots = locations.map { (user.library as NSString).appendingPathComponent($0) }
            + ["/Applications", user.inHome("Applications")]

        // Note this uses `core`, not `forClean`: Containers and Preferences are exactly
        // what Uninstall is here to remove, and are protected only from Clean.
        self.pathGuard = PathGuard(
            allowedRoots: roots,
            protectedPaths: ProtectedPaths.core(for: user) + extraProtectedPaths,
            resolver: resolver
        )
    }

    /// - Throws: `CancellationError` when cancelled.
    public func scan(app: InstalledApp) async throws -> LeftoverScan {
        var items: [LeftoverItem] = []
        var skipped: [SkippedPath] = []

        for location in locations {
            try Task.checkCancellation()
            let root = (library as NSString).appendingPathComponent(location)

            for entry in DirectoryListing.children(of: root) {
                try Task.checkCancellation()
                let entryName = (entry as NSString).lastPathComponent

                guard let confidence = LeftoverMatcher.match(
                    entryName: entryName,
                    location: location,
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier
                ) else { continue }

                // The guard runs before anything is measured or offered, so a refused
                // path never reaches a list a technician might reasonably tick wholesale.
                switch pathGuard.decide(entry) {
                case .denied(let denial):
                    skipped.append(SkippedPath(path: entry, reason: denial.explanation))
                case .allowed(let canonicalPath):
                    var isDirectory: ObjCBool = false
                    _ = FileManager.default.fileExists(atPath: canonicalPath, isDirectory: &isDirectory)

                    items.append(LeftoverItem(
                        path: canonicalPath,
                        sizeBytes: try sizer.size(of: canonicalPath),
                        isDirectory: isDirectory.boolValue,
                        confidence: confidence,
                        location: location
                    ))
                }
            }
        }

        return LeftoverScan(
            app: app,
            // Confident matches first, then largest first within each tier: the things
            // most certainly safe to remove sit at the top, and the judgement calls
            // gather together lower down instead of being sprinkled through the list.
            items: items.sorted {
                $0.confidence == $1.confidence
                    ? $0.sizeBytes > $1.sizeBytes
                    : $0.confidence == .confident
            },
            skipped: skipped
        )
    }
}
