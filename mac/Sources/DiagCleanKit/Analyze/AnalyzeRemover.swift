import Foundation

/// Removes exactly one item, to the Trash.
///
/// One at a time is deliberate and inherited from the CLI: Analyze can reach anywhere,
/// so there is no bulk selection to get wrong. Everything goes to the Trash rather than
/// being deleted, because unlike a cache this could be anything at all — and unlike
/// Uninstall, DiagClean has no idea what it is.
public struct AnalyzeRemover: Sendable {
    private let analyzeGuard: AnalyzeGuard

    public init(analyzeGuard: AnalyzeGuard = AnalyzeGuard()) {
        self.analyzeGuard = analyzeGuard
    }

    public func decide(_ entry: DiskEntry) -> AnalyzeDecision {
        analyzeGuard.decide(entry.path)
    }

    public func remove(_ entry: DiskEntry) -> AnalyzeRemovalReport {
        // Re-checked here against the same rules that allowed it to be offered. The
        // listing behind the confirmation may be minutes old.
        switch analyzeGuard.decide(entry.path) {
        case .denied(let denial):
            return AnalyzeRemovalReport(
                path: entry.path, name: entry.name, bytesFreed: 0,
                failure: "blocked at removal time: \(denial.explanation)"
            )
        case .allowed(let canonicalPath, _):
            guard FileManager.default.fileExists(atPath: canonicalPath) else {
                return AnalyzeRemovalReport(
                    path: entry.path, name: entry.name, bytesFreed: 0,
                    failure: "This item is no longer there."
                )
            }
            do {
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: canonicalPath), resultingItemURL: nil
                )
                return AnalyzeRemovalReport(
                    path: entry.path, name: entry.name, bytesFreed: entry.sizeBytes, failure: nil
                )
            } catch {
                return AnalyzeRemovalReport(
                    path: entry.path, name: entry.name, bytesFreed: 0,
                    failure: (error as NSError).localizedDescription
                )
            }
        }
    }
}
