import Foundation
import Observation
import DiagCleanKit

@MainActor
@Observable
final class AnalyzeViewModel {
    private(set) var currentPath: String
    private(set) var entries: [DiskEntry] = []
    private(set) var isScanning = false
    private(set) var unreadableCount = 0
    private(set) var lastRemoval: AnalyzeRemovalReport?
    private(set) var errorMessage: String?

    var selectedEntryID: DiskEntry.ID?
    var pendingRemoval: PendingRemoval?

    /// A removal waiting on confirmation, carrying the guard's verdict so the sheet can
    /// say what kind of thing this is rather than asking the same way about everything.
    struct PendingRemoval: Identifiable {
        let id = UUID()
        let entry: DiskEntry
        let sensitivity: RemovalSensitivity
    }

    private let analyzer = DirectoryAnalyzer()
    private let remover: AnalyzeRemover
    private let analyzeGuard: AnalyzeGuard
    private var scanTask: Task<Void, Never>?
    /// Sizes already measured, so going back up a level is instant. Invalidated for a
    /// path and all its ancestors when something under it is removed — a browser showing
    /// pre-deletion totals would be quietly lying.
    private var cache: [String: [DiskEntry]] = [:]

    init(user: UserPaths = .current()) {
        let analyzeGuard = AnalyzeGuard(user: user)
        self.analyzeGuard = analyzeGuard
        self.remover = AnalyzeRemover(analyzeGuard: analyzeGuard)
        self.currentPath = user.home
    }

    // MARK: - Derived state

    var breadcrumb: [(name: String, path: String)] {
        DirectoryAnalyzer.breadcrumb(for: currentPath)
    }

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }

    var selectedEntry: DiskEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var parentPath: String? {
        let parent = (currentPath as NSString).deletingLastPathComponent
        return parent == currentPath || parent.isEmpty ? nil : parent
    }

    /// The largest entry's size, used to scale the proportion bars. Scaling to the
    /// largest sibling rather than to the total keeps the bars readable when one item
    /// dominates, which in a disk browser is most of the time.
    var largestEntryBytes: Int64 { entries.first?.sizeBytes ?? 0 }

    func decision(for entry: DiskEntry) -> AnalyzeDecision {
        analyzeGuard.decide(entry.path)
    }

    // MARK: - Navigation

    func loadIfNeeded() {
        guard entries.isEmpty, !isScanning else { return }
        navigate(to: currentPath)
    }

    func navigate(to path: String) {
        scanTask?.cancel()
        currentPath = path
        selectedEntryID = nil
        lastRemoval = nil
        errorMessage = nil

        if let cached = cache[path] {
            entries = cached
            isScanning = false
            return
        }

        entries = []
        unreadableCount = 0
        isScanning = true

        scanTask = Task { [analyzer] in
            do {
                let listing = try await analyzer.listing(of: path) { entry in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentPath == path else { return }
                        // Inserted in size order as each measurement lands, so the list
                        // is useful while it is still filling rather than only after.
                        let index = self.entries.firstIndex { $0.sizeBytes < entry.sizeBytes } ?? self.entries.count
                        self.entries.insert(entry, at: index)
                    }
                }
                guard !Task.isCancelled, self.currentPath == path else { return }
                self.entries = listing.entries
                self.unreadableCount = listing.unreadableCount
                self.cache[path] = listing.entries
                self.isScanning = false
            } catch is CancellationError {
                self.isScanning = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isScanning = false
            }
        }
    }

    func open(_ entry: DiskEntry) {
        guard entry.isDirectory else { return }
        navigate(to: entry.path)
    }

    func goToParent() {
        guard let parentPath else { return }
        navigate(to: parentPath)
    }

    func rescan() {
        cache[currentPath] = nil
        navigate(to: currentPath)
    }

    // MARK: - Removal

    /// One item at a time, always. Analyze can reach anywhere, so there is deliberately
    /// no multi-selection to get wrong.
    func requestRemoval(of entry: DiskEntry) {
        switch analyzeGuard.decide(entry.path) {
        case .denied(let denial):
            errorMessage = denial.explanation
        case .allowed(_, let sensitivity):
            errorMessage = nil
            pendingRemoval = PendingRemoval(entry: entry, sensitivity: sensitivity)
        }
    }

    func confirmRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil

        let report = remover.remove(pending.entry)
        lastRemoval = report

        if report.succeeded {
            entries.removeAll { $0.id == pending.entry.id }
            selectedEntryID = nil
            invalidateCache(forPathAndAncestorsOf: pending.entry.path)
        } else {
            errorMessage = report.failure
        }
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    func dismissMessage() {
        errorMessage = nil
        lastRemoval = nil
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Every ancestor's cached total included the bytes that just went, so all of them
    /// are now wrong.
    private func invalidateCache(forPathAndAncestorsOf path: String) {
        var current = (path as NSString).deletingLastPathComponent
        while !current.isEmpty && current != "/" {
            cache[current] = nil
            current = (current as NSString).deletingLastPathComponent
        }
        cache["/"] = nil
        cache[currentPath] = entries
    }
}
