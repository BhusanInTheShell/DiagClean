import Foundation
import Observation
import DiagCleanKit

@MainActor
@Observable
final class UninstallViewModel {
    enum Phase {
        case loadingApps
        case browsing
        case removing
        case finished
    }

    private(set) var phase: Phase = .loadingApps
    private(set) var apps: [InstalledApp] = []
    private(set) var selectedApp: InstalledApp?
    private(set) var scan: LeftoverScan?
    private(set) var isScanningLeftovers = false
    private(set) var refusal: UninstallRefusal?
    private(set) var progress: UninstallProgress?
    private(set) var report: UninstallReport?
    private(set) var logURL: URL?
    private(set) var errorMessage: String?

    /// The bundle itself is a separate tick from its leftovers. Removing only the
    /// leftovers is a real thing a technician wants — repairing an app that has got
    /// itself into a bad state, without making them download it again.
    var includeApp = true
    var selectedLeftoverIDs: Set<LeftoverItem.ID> = []
    var isConfirmationPresented = false
    var searchText = ""

    private let lister: AppLister
    private let scanner: LeftoverScanner
    private let executor: UninstallExecutor
    private let runLog: RunLog
    private var scanTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?

    init(
        user: UserPaths = .current(),
        runLog: RunLog = RunLog()
    ) {
        let scanner = LeftoverScanner(user: user)
        self.lister = AppLister(user: user)
        self.scanner = scanner
        self.executor = UninstallExecutor(pathGuard: scanner.pathGuard)
        self.runLog = runLog
    }

    // MARK: - Derived state

    var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var leftovers: [LeftoverItem] { scan?.items ?? [] }

    var selectedLeftovers: [LeftoverItem] {
        leftovers.filter { selectedLeftoverIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedLeftovers.reduce(includeApp ? (selectedApp?.sizeBytes ?? 0) : 0) { $0 + $1.sizeBytes }
    }

    var selectedCount: Int { selectedLeftovers.count + (includeApp ? 1 : 0) }

    var canRemove: Bool { refusal == nil && selectedCount > 0 && !isScanningLeftovers }

    var likelyCount: Int { leftovers.filter { $0.confidence == .likely }.count }

    // MARK: - Loading

    func loadIfNeeded() {
        guard phase == .loadingApps, apps.isEmpty else { return }
        loadApps()
    }

    func loadApps() {
        phase = .loadingApps
        errorMessage = nil

        Task { [lister] in
            do {
                let found = try await lister.listApps()
                self.apps = found
                self.phase = .browsing
            } catch is CancellationError {
                self.phase = .browsing
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase = .browsing
            }
        }
    }

    /// Selecting an app immediately scans for its leftovers. The scan cannot modify
    /// anything, so making it automatic costs nothing and means the review list is
    /// already there when somebody looks for it.
    func select(_ app: InstalledApp) {
        guard selectedApp?.id != app.id else { return }

        scanTask?.cancel()
        selectedApp = app
        scan = nil
        selectedLeftoverIDs = []
        includeApp = true
        report = nil
        logURL = nil
        phase = .browsing
        refusal = executor.refusal(for: app)
        isScanningLeftovers = true

        scanTask = Task { [scanner] in
            do {
                let result = try await scanner.scan(app: app)
                guard !Task.isCancelled, self.selectedApp?.id == app.id else { return }
                self.scan = result
                // Only confident matches start ticked. A name-based guess is somebody's
                // decision to make, never a default they inherit.
                self.selectedLeftoverIDs = Set(
                    result.items.filter { $0.confidence.isSelectedByDefault }.map(\.id)
                )
                self.isScanningLeftovers = false
            } catch {
                guard !Task.isCancelled else { return }
                self.isScanningLeftovers = false
            }
        }
    }

    // MARK: - Selection

    func isSelected(_ item: LeftoverItem) -> Bool { selectedLeftoverIDs.contains(item.id) }

    func toggle(_ item: LeftoverItem) {
        if selectedLeftoverIDs.contains(item.id) {
            selectedLeftoverIDs.remove(item.id)
        } else {
            selectedLeftoverIDs.insert(item.id)
        }
    }

    func selectAllLeftovers() {
        selectedLeftoverIDs = Set(leftovers.map(\.id))
    }

    func deselectAllLeftovers() {
        selectedLeftoverIDs = []
    }

    // MARK: - Removing

    func requestConfirmation() {
        guard canRemove else { return }
        isConfirmationPresented = true
    }

    /// The only route to removal. Nothing else calls the executor.
    func confirmAndRemove() {
        isConfirmationPresented = false
        guard let app = selectedApp else { return }

        let plan = UninstallPlan(app: app, includeApp: includeApp, leftovers: selectedLeftovers)
        guard !plan.isEmpty else { return }

        runTask?.cancel()
        progress = nil
        phase = .removing

        runTask = Task { [executor, runLog] in
            let result = await executor.execute(plan: plan) { update in
                Task { @MainActor [weak self] in
                    self?.progress = update
                }
            }
            self.report = result
            self.logURL = runLog.record(plan: plan, report: result)
            self.phase = .finished
        }
    }

    func cancel() {
        runTask?.cancel()
        scanTask?.cancel()
    }

    /// Returns to the app list and rebuilds it, so a removed app is actually gone from
    /// the list rather than lingering as a stale row.
    func finish() {
        selectedApp = nil
        scan = nil
        selectedLeftoverIDs = []
        report = nil
        progress = nil
        apps = []
        loadApps()
    }
}
