import Foundation

/// The arithmetic that turns cumulative counters into the rates a dashboard shows, and
/// the thresholds that turn those rates into a verdict.
///
/// Deliberately pure and free of any system call, because this is where a dashboard
/// actually goes wrong. Reading a counter is easy; subtracting two of them correctly
/// when one has wrapped, or when the interval is zero, or when the first sample of a
/// session has no predecessor, is where a status view starts quietly reporting 4000% CPU
/// or a negative download rate. All of that is testable here without a machine in any
/// particular state.
public enum StatusCalculator {

    // MARK: - Rates

    /// CPU busy percentage between two tick samples.
    ///
    /// Returns `nil` rather than a number when the two samples cannot produce a real
    /// answer: identical samples, a counter that has gone backwards, or no elapsed
    /// ticks. A dashboard showing nothing for one refresh is honest; one showing a
    /// fabricated zero is not.
    public static func cpuPercent(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        guard current.total >= previous.total, current.busy >= previous.busy else {
            // Counters went backwards, which means a wrap or a reset. There is no
            // meaningful delta to report.
            return nil
        }
        let totalDelta = current.total - previous.total
        let busyDelta = current.busy - previous.busy
        guard totalDelta > 0 else { return nil }

        return min(100, max(0, Double(busyDelta) / Double(totalDelta) * 100))
    }

    /// Bytes per second between two counter samples over `interval` seconds.
    public static func networkRates(
        from previous: NetworkCounters,
        to current: NetworkCounters,
        interval: TimeInterval
    ) -> NetworkRates? {
        guard interval > 0 else { return nil }
        guard current.bytesReceived >= previous.bytesReceived,
              current.bytesSent >= previous.bytesSent else {
            // Interface counters reset when an interface goes down and comes back, which
            // happens routinely on a laptop moving between networks.
            return nil
        }

        return NetworkRates(
            downloadBytesPerSecond: Double(current.bytesReceived - previous.bytesReceived) / interval,
            uploadBytesPerSecond: Double(current.bytesSent - previous.bytesSent) / interval
        )
    }

    /// Per-process CPU percentage between two samples.
    ///
    /// A process's percentage is of a single core, matching Activity Monitor, so a
    /// thread-saturating process on an 8-core machine reads 100% rather than 12%.
    /// Processes absent from the earlier sample are skipped rather than credited with
    /// all the CPU time they have used since launching — that is how a status view ends
    /// up claiming a newly-opened app is using 900%.
    public static func processUsage(
        from previous: [ProcessSample],
        to current: [ProcessSample],
        interval: TimeInterval,
        limit: Int = 5
    ) -> [ProcessUsage] {
        guard interval > 0 else { return [] }
        let previousByPID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return current
            .compactMap { sample -> ProcessUsage? in
                guard let earlier = previousByPID[sample.id] else { return nil }
                guard sample.cpuNanoseconds >= earlier.cpuNanoseconds else { return nil }

                let deltaSeconds = Double(sample.cpuNanoseconds - earlier.cpuNanoseconds) / 1_000_000_000
                let percent = deltaSeconds / interval * 100
                // A low floor on purpose. On a quiet machine a 0.1% cutoff empties the
                // list entirely, and "nothing is busy" is a much less useful answer than
                // naming the handful of things that are ticking over.
                guard percent >= 0.05 else { return nil }

                return ProcessUsage(
                    pid: sample.id, name: sample.name,
                    cpuPercent: percent, residentBytes: sample.residentBytes
                )
            }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Verdicts

    /// Sustained high CPU is worth flagging; a brief spike is not, but a dashboard
    /// refreshing every couple of seconds cannot tell the difference on its own, so the
    /// thresholds are set where a technician would actually start looking.
    public static func cpuHealth(percent: Double) -> HealthLevel {
        switch percent {
        case ..<70: return .normal
        case ..<90: return .elevated
        default: return .critical
        }
    }

    /// Prefers macOS's own pressure verdict. Used-percentage is a poor signal on its
    /// own — a healthy Mac routinely sits above 80% because unused RAM is wasted RAM —
    /// so it is only the fallback when pressure is unreadable.
    public static func memoryHealth(_ sample: MemorySample) -> HealthLevel {
        if let pressure = sample.pressureLevel {
            return pressure
        }
        switch sample.usedFraction {
        case ..<0.80: return .normal
        case ..<0.92: return .elevated
        default: return .critical
        }
    }

    /// Absolute free space is the primary signal; proportion can only escalate that
    /// verdict, never raise one on its own.
    ///
    /// Either measure alone gets this wrong in an obvious way. A 4 TB disk at 95% full
    /// has 200 GB free and is completely fine, so proportion alone cries wolf; a 128 GB
    /// disk at 88% full has 15 GB and is starting to hurt, so proportion alone is also
    /// the only thing that catches a disk that is small to begin with. They have to
    /// agree before the verdict moves.
    public static func diskHealth(_ sample: DiskSpaceSample) -> HealthLevel {
        let freeFraction = 1 - sample.usedFraction
        let freeGigabytes = Double(sample.availableBytes) / 1_000_000_000

        if freeGigabytes < 5 || (freeFraction < 0.05 && freeGigabytes < 25) { return .critical }
        if freeGigabytes < 15 || (freeFraction < 0.12 && freeGigabytes < 50) { return .elevated }
        return .normal
    }

    /// Only meaningful while running on battery. Plugged in at 8% is a machine that is
    /// charging, not a machine in trouble.
    public static func batteryHealth(_ sample: BatterySample) -> HealthLevel {
        guard !sample.isPluggedIn else { return .normal }
        switch sample.percent {
        case ..<10: return .critical
        case ..<20: return .elevated
        default: return .normal
        }
    }

    /// The worst of everything, for the menu bar and the window's one-line summary.
    public static func overallHealth(_ status: SystemStatus) -> HealthLevel {
        var levels: [HealthLevel] = [
            cpuHealth(percent: status.cpuPercent),
            memoryHealth(status.memory),
            diskHealth(status.disk),
        ]
        if let battery = status.battery {
            levels.append(batteryHealth(battery))
        }
        return levels.max() ?? .normal
    }
}
