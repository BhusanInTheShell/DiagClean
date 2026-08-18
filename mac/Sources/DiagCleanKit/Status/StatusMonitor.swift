import Foundation

/// Holds the previous counter reading so each refresh can be turned into a rate.
///
/// Separated from the view model so the sampling logic — including the awkward first
/// tick, where there is nothing to compare against — is exercisable without a UI.
public final class StatusSampler: @unchecked Sendable {
    private let probe: SystemProbing
    private let now: @Sendable () -> Date

    private var previousTicks: CPUTicks?
    private var previousNetwork: NetworkCounters?
    private var previousProcesses: [ProcessSample] = []
    private var previousSampledAt: Date?

    /// Carried across refreshes so a momentary unreadable counter shows the last known
    /// figure rather than blinking to zero and back.
    private var lastCPUPercent: Double = 0
    private var lastNetworkRates: NetworkRates = .zero
    private var lastProcesses: [ProcessUsage] = []

    public init(probe: SystemProbing = LiveSystemProbe(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.probe = probe
        self.now = now
    }

    /// True once a second reading has happened and rates are real rather than assumed.
    public private(set) var hasRates = false

    public func sample() -> SystemStatus? {
        let sampledAt = now()
        let interval = previousSampledAt.map { sampledAt.timeIntervalSince($0) } ?? 0

        guard let memory = probe.memory(), let disk = probe.diskSpace() else {
            // Without memory and disk there is no dashboard worth showing, and inventing
            // zeroes for them would be worse than showing nothing.
            return nil
        }

        if let ticks = probe.cpuTicks() {
            if let previous = previousTicks, let percent = StatusCalculator.cpuPercent(from: previous, to: ticks) {
                lastCPUPercent = percent
                hasRates = true
            }
            previousTicks = ticks
        }

        if let counters = probe.networkCounters() {
            if let previous = previousNetwork,
               let rates = StatusCalculator.networkRates(from: previous, to: counters, interval: interval) {
                lastNetworkRates = rates
            }
            previousNetwork = counters
        }

        let (processSamples, unreadable) = probe.processes()
        if !previousProcesses.isEmpty, interval > 0 {
            lastProcesses = StatusCalculator.processUsage(
                from: previousProcesses, to: processSamples, interval: interval
            )
        }
        previousProcesses = processSamples
        previousSampledAt = sampledAt

        return SystemStatus(
            cpuPercent: lastCPUPercent,
            coreCount: probe.coreCount(),
            loadAverage: probe.loadAverage(),
            memory: memory,
            disk: disk,
            network: lastNetworkRates,
            battery: probe.battery(),
            uptime: probe.uptime(),
            topProcesses: lastProcesses,
            unreadableProcessCount: unreadable,
            sampledAt: sampledAt
        )
    }
}
