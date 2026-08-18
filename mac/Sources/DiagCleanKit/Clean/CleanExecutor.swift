import Foundation

public struct CleanProgress: Sendable {
    public let itemsCompleted: Int
    public let totalItems: Int
    public let bytesFreed: Int64
    public let currentPath: String
}

/// The only code in DiagClean that removes anything.
///
/// Everything else scans, measures and presents. Keeping deletion to a single small
/// type means the safety rules have exactly one place to be enforced and one place to
/// be reviewed, and it is the reason the CLI's equivalent has held up.
///
/// Two rules, both non-negotiable:
///
///   1. **Every item is re-checked against its guard immediately before removal.** The
///      plan was built from a scan that may be minutes old by the time somebody reads
///      it, thinks about it and confirms. Nothing is trusted for having appeared in a
///      preview.
///   2. **Removal is permanent, and the UI says so.** Caches and temp files are moved
///      to the Trash by nobody, because that would relocate the bytes instead of
///      reclaiming them and the technician would have freed nothing at all. Uninstall,
///      where the stakes are entirely different, uses the Trash.
public struct CleanExecutor: Sendable {
    private let guardsByCategory: [CleanCategory: PathGuard]
    private let now: @Sendable () -> Date

    public init(
        targets: [CleanTarget],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.now = now
        self.guardsByCategory = Dictionary(
            targets.map { ($0.category, $0.pathGuard) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Cancellation is honoured between items, never during one. A directory removal is
    /// not resumable, so stopping halfway through would leave a cache in a state no
    /// caller could describe; the loop finishes the item in hand and then stops.
    public func execute(
        plan: CleanPlan,
        progress: @Sendable (CleanProgress) -> Void = { _ in }
    ) async -> CleanReport {
        let startedAt = now()
        var bytesFreed: Int64 = 0
        var itemsRemoved = 0
        var failures: [CleanFailure] = []
        var wasCancelled = false

        for (index, item) in plan.items.enumerated() {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            guard let pathGuard = guardsByCategory[item.category] else {
                // No guard means no authority to delete. This should be unreachable —
                // plans are built from scans run against these same targets — so it is
                // a bug rather than a user-facing condition, and it fails closed.
                failures.append(CleanFailure(
                    path: item.path,
                    reason: "no guard is registered for \(item.category.rawValue); refused"
                ))
                continue
            }

            switch pathGuard.decide(item.path) {
            case .denied(let denial):
                failures.append(CleanFailure(
                    path: item.path,
                    reason: "blocked at removal time: \(denial.explanation)"
                ))
            case .allowed(let canonicalPath):
                do {
                    // Gone already (a browser cleared its own cache since the scan) is
                    // a success, not a failure: the bytes are free either way, and
                    // reporting it as an error would train technicians to ignore errors.
                    if FileManager.default.fileExists(atPath: canonicalPath) {
                        try FileManager.default.removeItem(atPath: canonicalPath)
                    }
                    bytesFreed += item.sizeBytes
                    itemsRemoved += 1
                } catch {
                    failures.append(CleanFailure(
                        path: item.path,
                        reason: (error as NSError).localizedDescription
                    ))
                }
            }

            progress(CleanProgress(
                itemsCompleted: index + 1,
                totalItems: plan.itemCount,
                bytesFreed: bytesFreed,
                currentPath: item.path
            ))
        }

        return CleanReport(
            bytesFreed: bytesFreed,
            itemsRemoved: itemsRemoved,
            failures: failures,
            wasCancelled: wasCancelled,
            startedAt: startedAt,
            finishedAt: now()
        )
    }
}
