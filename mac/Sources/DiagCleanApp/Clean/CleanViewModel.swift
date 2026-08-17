import Foundation
import Observation
import DiagCleanKit

/// One item as the review list shows it: several cache directories belonging to the
/// same app, collapsed into a row a person recognises. A technician decides about
/// "Brave Browser", not about four separate Dawn cache directories.
struct CleanRowGroup: Identifiable, Hashable {
    let id: String
    let label: String
    let items: [CleanItem]

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var primaryPath: String { items.first?.path ?? "" }
    var additionalLocationCount: Int { max(0, items.count - 1) }
}

@MainActor
@Observable
final class CleanViewModel {
    enum Phase {
        case idle
        case scanning
        case reviewing
        case cleaning
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var scan: CleanScan?
    private(set) var scanStatus: String = ""
    private(set) var cleanProgress: CleanProgress?
    private(set) var report: CleanReport?
    private(set) var lastPlan: CleanPlan?
    private(set) var logURL: URL?
    private(set) var errorMessage: String?

    /// Selection is by item id. Everything found starts selected — a technician who
    /// opened Clean intends to clean — but the confirmation step means a full selection
    /// still can't become a deletion without somebody reading the list and saying yes.
    var selectedItemIDs: Set<CleanItem.ID> = []
    var isConfirmationPresented = false

    private let targets: [CleanTarget]
    private let scanner: CleanScanner
    private let executor: CleanExecutor
    private let runLog: RunLog
    private var runningTask: Task<Void, Never>?

    init(
        targets: [CleanTarget] = CleanScanner.defaultTargets(),
        runLog: RunLog = RunLog()
    ) {
        self.targets = targets
        self.scanner = CleanScanner(targets: targets)
        self.executor = CleanExecutor(targets: targets)
        self.runLog = runLog
    }

    // MARK: - Derived state

    var categories: [CategoryScan] { scan?.categories ?? [] }

    var selectedItems: [CleanItem] {
        (scan?.allItems ?? []).filter { selectedItemIDs.contains($0.id) }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var selectedCount: Int { selectedItems.count }

    var hasFindings: Bool { (scan?.itemCount ?? 0) > 0 }

    var skippedCount: Int {
        categories.reduce(0) { $0 + $1.skipped.count }
    }

    /// Cache directories belonging to the same app, merged into one row per app and
    /// ordered largest first — the order in which somebody would want to make decisions.
    func groups(in category: CategoryScan) -> [CleanRowGroup] {
        Dictionary(grouping: category.items, by: \.ownerLabel)
            .map { label, items in
                CleanRowGroup(
                    id: "\(category.category.rawValue).\(label)",
                    label: label,
                    items: items.sorted { $0.sizeBytes > $1.sizeBytes }
                )
            }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Selection

    func isSelected(_ group: CleanRowGroup) -> Bool {
        !group.items.isEmpty && group.items.allSatisfy { selectedItemIDs.contains($0.id) }
    }

    func isPartiallySelected(_ group: CleanRowGroup) -> Bool {
        let selected = group.items.filter { selectedItemIDs.contains($0.id) }.count
        return selected > 0 && selected < group.items.count
    }

    func toggle(_ group: CleanRowGroup) {
        if isSelected(group) {
            group.items.forEach { selectedItemIDs.remove($0.id) }
        } else {
            group.items.forEach { selectedItemIDs.insert($0.id) }
        }
    }

    func isSelected(_ category: CategoryScan) -> Bool {
        !category.items.isEmpty && category.items.allSatisfy { selectedItemIDs.contains($0.id) }
    }

    func isPartiallySelected(_ category: CategoryScan) -> Bool {
        let selected = category.items.filter { selectedItemIDs.contains($0.id) }.count
        return selected > 0 && selected < category.items.count
    }

    func toggle(_ category: CategoryScan) {
        if isSelected(category) {
            category.items.forEach { selectedItemIDs.remove($0.id) }
        } else {
            category.items.forEach { selectedItemIDs.insert($0.id) }
        }
    }

    // MARK: - Scanning

    /// Safe to call on appear: scanning cannot modify anything, so the screen can
    /// arrive with the answer already on it rather than with a button asking permission
    /// to go and find out.
    func scanIfNeeded() {
        guard phase == .idle else { return }
        startScan()
    }

    func startScan() {
        runningTask?.cancel()
        phase = .scanning
        scanStatus = "Starting…"
        errorMessage = nil
        report = nil
        logURL = nil

        runningTask = Task { [scanner] in
            do {
                let result = try await scanner.scan { progress in
                    Task { @MainActor [weak self] in
                        self?.scanStatus = Self.describe(progress)
                    }
                }
                guard !Task.isCancelled else { return }
                self.scan = result
                self.selectedItemIDs = Set(result.allItems.map(\.id))
                self.phase = .reviewing
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase = .idle
            }
        }
    }

    private static func describe(_ progress: ScanProgress) -> String {
        guard let path = progress.currentPath else {
            return "Scanning \(progress.category.title.lowercased())…"
        }
        return "Scanning \(PathDisplay.abbreviate(path))"
    }

    // MARK: - Cleaning

    func requestConfirmation() {
        guard selectedCount > 0 else { return }
        isConfirmationPresented = true
    }

    /// The only route to deletion in the entire app. Nothing else calls the executor.
    func confirmAndClean() {
        isConfirmationPresented = false
        let plan = CleanPlan(items: selectedItems)
        guard !plan.isEmpty else { return }

        runningTask?.cancel()
        lastPlan = plan
        cleanProgress = nil
        phase = .cleaning

        runningTask = Task { [executor, runLog] in
            let result = await executor.execute(plan: plan) { progress in
                Task { @MainActor [weak self] in
                    self?.cleanProgress = progress
                }
            }
            self.report = result
            self.logURL = runLog.record(plan: plan, report: result)
            self.phase = .finished
        }
    }

    /// Cancels whichever long-running operation is in flight. During a clean this stops
    /// between items rather than mid-item, so the machine is never left in a state the
    /// report can't describe.
    func cancel() {
        runningTask?.cancel()
    }

    /// Back to a fresh scan after a run, so the numbers on screen are never stale
    /// figures from before the deletion.
    func startOver() {
        scan = nil
        selectedItemIDs = []
        report = nil
        lastPlan = nil
        cleanProgress = nil
        phase = .idle
        startScan()
    }
}
