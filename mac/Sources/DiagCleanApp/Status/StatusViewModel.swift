import Foundation
import Observation
import DiagCleanKit

@MainActor
@Observable
final class StatusViewModel {
    private(set) var status: SystemStatus?
    private(set) var isRunning = false

    /// Two seconds is fast enough to feel live and slow enough that the app is not
    /// itself a meaningful load on the machine it is measuring.
    private let interval: TimeInterval = 2

    private let sampler: StatusSampler
    private var pollTask: Task<Void, Never>?

    init(sampler: StatusSampler = StatusSampler()) {
        self.sampler = sampler
    }

    var overallHealth: HealthLevel {
        status.map(StatusCalculator.overallHealth) ?? .normal
    }

    var hasRates: Bool { sampler.hasRates }

    /// Polling stops whenever the view goes away. A dashboard that keeps sampling behind
    /// a hidden window is a battery drain nobody asked for, and this app is supposed to
    /// stay out of the way.
    func start() {
        guard pollTask == nil else { return }
        isRunning = true

        pollTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                guard let self else { return }
                if let sample = self.sampler.sample() {
                    self.status = sample
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
    }
}
