import Foundation

/// Lists one directory at a time, measuring each child's recursive size.
///
/// Sizes are computed concurrently, one task per child, and reported as each finishes.
/// The CLI shells out to `du -k -d 1`, which is a single fast call but arrives all at
/// once and cannot be interrupted. Measuring natively costs a little more wall time on a
/// big tree and buys two things worth more than that: rows appear as they are measured
/// rather than after a long blank pause, and Cancel actually stops the work.
///
/// Only one level is measured per navigation. Descending re-measures the level below,
/// which is why moving through a large tree stays responsive instead of paying for the
/// whole disk up front.
public struct DirectoryAnalyzer: Sendable {
    private let sizer: DirectorySizer

    public init(sizer: DirectorySizer = DirectorySizer()) {
        self.sizer = sizer
    }

    /// - Parameter onEntry: called as each child finishes measuring, on whatever
    ///   executor the task group happens to be running. Callers marshal to the main
    ///   actor themselves.
    /// - Throws: `CancellationError` when cancelled.
    public func listing(
        of path: String,
        onEntry: @Sendable @escaping (DiskEntry) -> Void = { _ in }
    ) async throws -> DirectoryListing {
        let standardized = PathGuard.standardize(path)
        let url = URL(fileURLWithPath: standardized)

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: []
        ) else {
            return DirectoryListing(path: standardized, entries: [], unreadableCount: 1)
        }

        let sizer = self.sizer
        let entries = try await withThrowingTaskGroup(of: DiskEntry?.self) { group in
            for child in children {
                group.addTask {
                    try Task.checkCancellation()

                    let values = try? child.resourceValues(forKeys: [
                        .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
                    ])
                    // A link is listed at its own trivial size and never followed —
                    // otherwise a link into a huge tree would report bytes that removing
                    // it would not actually free.
                    let isLink = values?.isSymbolicLink == true
                    let isDirectory = values?.isDirectory == true && !isLink

                    let size: Int64 = isLink ? 0 : ((try? sizer.size(of: child.path)) ?? 0)
                    let entry = DiskEntry(
                        path: child.path,
                        name: child.lastPathComponent,
                        sizeBytes: size,
                        isDirectory: isDirectory,
                        lastModified: values?.contentModificationDate,
                        isPartial: false
                    )
                    onEntry(entry)
                    return entry
                }
            }

            var results: [DiskEntry] = []
            for try await entry in group {
                if let entry { results.append(entry) }
            }
            return results
        }

        return DirectoryListing(
            path: standardized,
            // Largest first: the whole reason somebody opened this screen is to find
            // out what is taking up the space.
            entries: entries.sorted { $0.sizeBytes > $1.sizeBytes },
            unreadableCount: 0
        )
    }

    /// Breadcrumb components from the volume root down to `path`.
    public static func breadcrumb(for path: String) -> [(name: String, path: String)] {
        let standardized = PathGuard.standardize(path)
        var result: [(String, String)] = []
        var current = standardized

        while current != "/" && !current.isEmpty {
            result.append(((current as NSString).lastPathComponent, current))
            current = (current as NSString).deletingLastPathComponent
        }
        result.append(("Macintosh HD", "/"))
        return result.reversed()
    }
}
