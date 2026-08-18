import Foundation
import Observation
import DiagCleanKit

@MainActor
@Observable
final class OptimizeViewModel {
    enum Phase {
        case choosing
        case running
        case finished
    }

    private(set) var phase: Phase = .choosing
    private(set) var progress: OptimizeProgress?
    private(set) var report: OptimizeReport?

    var selectedIDs: Set<String> = Set(
        OptimizationCatalog.all.filter(\.isSelectedByDefault).map(\.id)
    )
    var isConfirmationPresented = false

    private let service = OptimizeService()
    private var runTask: Task<Void, Never>?

    let available = OptimizationCatalog.available()
    let unavailable = OptimizationCatalog.unavailable()

    var selectedActions: [OptimizationAction] {
        available.filter { selectedIDs.contains($0.id) }
    }

    var selectedCount: Int { selectedActions.count }
    var canRun: Bool { selectedCount > 0 && phase != .running }

    /// Actions in the selection that the user will visibly notice. Drives the extra
    /// warning in the confirmation, so "restart Finder" never goes through as a quiet
    /// tick among four harmless ones.
    var disruptiveSelection: [OptimizationAction] {
        selectedActions.filter { $0.impact.isDisruptive }
    }

    func isSelected(_ action: OptimizationAction) -> Bool { selectedIDs.contains(action.id) }

    func toggle(_ action: OptimizationAction) {
        if selectedIDs.contains(action.id) {
            selectedIDs.remove(action.id)
        } else {
            selectedIDs.insert(action.id)
        }
    }

    func requestConfirmation() {
        guard canRun else { return }
        isConfirmationPresented = true
    }

    /// The only route to running anything. Nothing else calls the service.
    func confirmAndRun() {
        isConfirmationPresented = false
        let actions = selectedActions
        guard !actions.isEmpty else { return }

        runTask?.cancel()
        progress = nil
        phase = .running

        runTask = Task { [service] in
            let result = await service.run(actions: actions) { update in
                Task { @MainActor [weak self] in
                    self?.progress = update
                }
            }
            self.report = result
            self.phase = .finished
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    func startOver() {
        report = nil
        progress = nil
        phase = .choosing
    }
}
