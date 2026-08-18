import Foundation

/// How worried to be about a single metric. The point of a health dashboard rather than
/// a number readout is that a technician can glance at it and know whether anything
/// needs attention, so every metric carries its own verdict.
public enum HealthLevel: Int, Sendable, Comparable, CaseIterable {
    case normal
    case elevated
    case critical

    public static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Raw cumulative samples
//
// Everything the OS reports as a counter-since-boot lands here untouched. Turning two
// of these into a rate is `StatusCalculator`'s job, and keeping that split means the
// arithmetic is testable without a machine in a particular state.

public struct CPUTicks: Sendable, Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public var total: UInt64 { user &+ system &+ idle &+ nice }
    public var busy: UInt64 { user &+ system &+ nice }

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct NetworkCounters: Sendable, Equatable {
    public let bytesReceived: UInt64
    public let bytesSent: UInt64

    public init(bytesReceived: UInt64, bytesSent: UInt64) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
    }
}

public struct MemorySample: Sendable, Equatable {
    public let totalBytes: UInt64
    /// Active + wired + compressed, the same proxy the CLI uses and roughly what
    /// Activity Monitor calls "Memory Used".
    public let usedBytes: UInt64
    public let swapUsedBytes: UInt64
    /// macOS's own pressure verdict, which is a better signal than used-percentage:
    /// a Mac can sit at 90% used and be perfectly happy. `nil` when unreadable.
    public let pressureLevel: HealthLevel?

    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public init(totalBytes: UInt64, usedBytes: UInt64, swapUsedBytes: UInt64, pressureLevel: HealthLevel?) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressureLevel = pressureLevel
    }
}

public struct DiskSpaceSample: Sendable, Equatable {
    public let totalBytes: Int64
    /// What Finder and System Settings report as available, which counts space macOS
    /// can reclaim on demand. The CLI reports the raw figure instead, which on a real
    /// machine reads several gigabytes lower than the number the user is looking at —
    /// and a tool that disagrees with Finder looks broken even when it is being precise.
    public let availableBytes: Int64
    /// The gap between that and the raw free figure: space currently occupied but
    /// reclaimable. Named explicitly so the headline number is never a mystery.
    public let purgeableBytes: Int64

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public init(totalBytes: Int64, availableBytes: Int64, purgeableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.purgeableBytes = purgeableBytes
    }
}

public struct BatterySample: Sendable, Equatable {
    public let percent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    /// Minutes remaining, when macOS is willing to estimate. It reports −1 while still
    /// working it out, which is reported here as `nil` rather than as a number.
    public let minutesRemaining: Int?
    public let cycleCount: Int?
    public let healthPercent: Int?

    public init(
        percent: Int, isCharging: Bool, isPluggedIn: Bool,
        minutesRemaining: Int?, cycleCount: Int?, healthPercent: Int?
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }
}

public struct LoadAverage: Sendable, Equatable {
    public let oneMinute: Double
    public let fiveMinutes: Double
    public let fifteenMinutes: Double

    public init(oneMinute: Double, fiveMinutes: Double, fifteenMinutes: Double) {
        self.oneMinute = oneMinute
        self.fiveMinutes = fiveMinutes
        self.fifteenMinutes = fifteenMinutes
    }
}

/// Cumulative CPU time for one process. Rates come from comparing two of these.
public struct ProcessSample: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let name: String
    public let cpuNanoseconds: UInt64
    public let residentBytes: UInt64

    public init(pid: Int32, name: String, cpuNanoseconds: UInt64, residentBytes: UInt64) {
        self.id = pid
        self.name = name
        self.cpuNanoseconds = cpuNanoseconds
        self.residentBytes = residentBytes
    }
}

public struct ProcessUsage: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let name: String
    public let cpuPercent: Double
    public let residentBytes: UInt64

    public init(pid: Int32, name: String, cpuPercent: Double, residentBytes: UInt64) {
        self.id = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }
}

/// One complete reading, ready to display. Every optional here means "this machine does
/// not have that, or would not tell us" — never a zero standing in for missing data.
public struct SystemStatus: Sendable {
    public let cpuPercent: Double
    public let coreCount: Int
    public let loadAverage: LoadAverage?
    public let memory: MemorySample
    public let disk: DiskSpaceSample
    public let network: NetworkRates
    public let battery: BatterySample?
    public let uptime: TimeInterval
    public let topProcesses: [ProcessUsage]
    /// Processes macOS would not let this app read without elevation. Reported rather
    /// than hidden: a "top processes" list quietly missing 40% of the machine is a list
    /// that will eventually mislead somebody hunting a runaway daemon.
    public let unreadableProcessCount: Int
    public let sampledAt: Date

    public init(
        cpuPercent: Double, coreCount: Int, loadAverage: LoadAverage?,
        memory: MemorySample, disk: DiskSpaceSample, network: NetworkRates,
        battery: BatterySample?, uptime: TimeInterval,
        topProcesses: [ProcessUsage], unreadableProcessCount: Int, sampledAt: Date
    ) {
        self.cpuPercent = cpuPercent
        self.coreCount = coreCount
        self.loadAverage = loadAverage
        self.memory = memory
        self.disk = disk
        self.network = network
        self.battery = battery
        self.uptime = uptime
        self.topProcesses = topProcesses
        self.unreadableProcessCount = unreadableProcessCount
        self.sampledAt = sampledAt
    }
}

public struct NetworkRates: Sendable, Equatable {
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public static let zero = NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}
