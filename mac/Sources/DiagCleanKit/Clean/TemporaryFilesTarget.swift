import Foundation

/// The invoking user's per-boot temp directory (`$TMPDIR`, a `/var/folders/…/T` path).
///
/// Two deliberate narrowings versus the CLI's equivalent:
///
///   * **`/private/tmp` is not touched.** It is shared between every user and every
///     daemon on the machine, and it is where running software keeps live Unix sockets
///     and lock files. Clearing it reclaims a little space and can break software that
///     is running at that moment, which is the wrong side of the trade for a tool a
///     technician runs on somebody else's machine.
///   * **Only entries untouched for at least a day are offered.** A temp file modified
///     in the last few minutes is overwhelmingly likely to belong to something running
///     right now. Waiting a day costs almost nothing in reclaimed bytes and removes an
///     entire class of "the app crashed right after you cleaned" incidents.
public struct TemporaryFilesTarget: CleanTarget {
    public let category = CleanCategory.temporaryFiles
    public let pathGuard: PathGuard

    private let tempRoot: String
    private let minimumAge: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        tempRoot: String,
        protectedPaths: [String],
        minimumAge: TimeInterval = 24 * 60 * 60,
        resolver: PathResolving = LivePathResolver(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tempRoot = PathGuard.standardize(tempRoot)
        self.minimumAge = minimumAge
        self.now = now
        self.pathGuard = PathGuard(
            allowedRoots: [self.tempRoot],
            protectedPaths: protectedPaths,
            resolver: resolver
        )
    }

    public static func currentUserTempRoot() -> String {
        NSTemporaryDirectory()
    }

    public func candidates() -> [Candidate] {
        let cutoff = now().addingTimeInterval(-minimumAge)

        return FileSystemListing.children(of: tempRoot)
            .filter { path in
                guard let modified = FileSystemListing.modificationDate(of: path) else {
                    // No readable timestamp means no way to establish it is stale, and
                    // the whole point of the age rule is not to guess.
                    return false
                }
                return modified < cutoff
            }
            .map { Candidate(path: $0, ownerLabel: "Temporary Files") }
    }
}
