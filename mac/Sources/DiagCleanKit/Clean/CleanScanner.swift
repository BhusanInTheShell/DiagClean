import Foundation

public struct ScanProgress: Sendable {
    public let category: CleanCategory
    public let completedCategories: Int
    public let totalCategories: Int
    public let currentPath: String?
}

/// Turns targets into a measured, guard-checked preview. Read-only from start to
/// finish — nothing in this file can modify the disk, which is the property that makes
/// it safe to run a scan automatically when the screen opens.
public struct CleanScanner: Sendable {
    private let targets: [CleanTarget]
    private let sizer: DirectorySizer
    private let now: @Sendable () -> Date

    public init(
        targets: [CleanTarget],
        sizer: DirectorySizer = DirectorySizer(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.targets = targets
        self.sizer = sizer
        self.now = now
    }

    /// The standard macOS target set, each wired to its own guard. Kept in one place so
    /// every target's allowed roots can be reviewed side by side rather than hunted for
    /// across five files.
    public static func defaultTargets(
        user: UserPaths = .current(),
        extraProtectedPaths: [String] = [],
        resolver: PathResolving = LivePathResolver()
    ) -> [CleanTarget] {
        let protected = ProtectedPaths.forClean(for: user) + extraProtectedPaths
        return [
            TemporaryFilesTarget(
                tempRoot: TemporaryFilesTarget.currentUserTempRoot(),
                protectedPaths: protected,
                resolver: resolver
            ),
            BrowserCachesTarget(user: user, protectedPaths: protected, resolver: resolver),
            ApplicationCachesTarget(user: user, protectedPaths: protected, resolver: resolver),
        ]
    }

    /// - Throws: `CancellationError` when cancelled. A cancelled scan produces nothing;
    ///   a half-measured preview is worse than no preview, because its totals would be
    ///   wrong in a direction nobody could see.
    public func scan(progress: @Sendable (ScanProgress) -> Void = { _ in }) async throws -> CleanScan {
        let startedAt = now()
        var results: [CategoryScan] = []

        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            progress(ScanProgress(
                category: target.category,
                completedCategories: index,
                totalCategories: targets.count,
                currentPath: nil
            ))

            results.append(try scan(target: target, index: index, progress: progress))
        }

        return CleanScan(categories: results, startedAt: startedAt, finishedAt: now())
    }

    private func scan(
        target: CleanTarget,
        index: Int,
        progress: @Sendable (ScanProgress) -> Void
    ) throws -> CategoryScan {
        var items: [CleanItem] = []
        var skipped: [SkippedPath] = []

        for candidate in target.candidates() {
            try Task.checkCancellation()
            progress(ScanProgress(
                category: target.category,
                completedCategories: index,
                totalCategories: targets.count,
                currentPath: candidate.path
            ))

            // The guard runs before anything is measured, let alone offered. A path the
            // guard refuses never reaches the preview at all, so it cannot be selected
            // by a technician who reasonably assumes everything shown is fair game.
            switch target.pathGuard.decide(candidate.path) {
            case .denied(let denial):
                skipped.append(SkippedPath(path: candidate.path, reason: denial.explanation))
            case .allowed(let canonicalPath):
                let size = try sizer.size(of: canonicalPath)
                // Zero-byte entries are real but useless to show: they add rows to the
                // review list without adding anything to reclaim.
                guard size > 0 else { continue }

                var isDirectory: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: canonicalPath, isDirectory: &isDirectory)

                items.append(CleanItem(
                    path: canonicalPath,
                    category: target.category,
                    ownerLabel: candidate.ownerLabel,
                    sizeBytes: size,
                    isDirectory: isDirectory.boolValue,
                    lastModified: DirectoryListing.modificationDate(of: canonicalPath)
                ))
            }
        }

        return CategoryScan(
            category: target.category,
            items: items.sorted { $0.sizeBytes > $1.sizeBytes },
            skipped: skipped
        )
    }
}
