import Foundation
import Testing
@testable import DiagCleanKit

/// A probe whose readings the test drives directly, so the sampler's handling of the
/// first tick and of momentarily unreadable counters can be pinned down exactly.
private final class StubProbe: SystemProbing, @unchecked Sendable {
    var ticks: CPUTicks? = CPUTicks(user: 0, system: 0, idle: 1000)
    var net: NetworkCounters? = NetworkCounters(bytesReceived: 0, bytesSent: 0)
    var mem: MemorySample? = MemorySample(
        totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, swapUsedBytes: 0, pressureLevel: .normal
    )
    var disk: DiskSpaceSample? = DiskSpaceSample(
        totalBytes: 500_000_000_000, availableBytes: 250_000_000_000, purgeableBytes: 0
    )
    var procs: [ProcessSample] = []
    var unreadable = 0

    func cpuTicks() -> CPUTicks? { ticks }
    func coreCount() -> Int { 8 }
    func loadAverage() -> LoadAverage? { LoadAverage(oneMinute: 1, fiveMinutes: 1, fifteenMinutes: 1) }
    func memory() -> MemorySample? { mem }
    func diskSpace() -> DiskSpaceSample? { disk }
    func networkCounters() -> NetworkCounters? { net }
    func battery() -> BatterySample? { nil }
    func uptime() -> TimeInterval { 3600 }
    func processes() -> (samples: [ProcessSample], unreadable: Int) { (procs, unreadable) }
}

@Suite("StatusSampler")
struct StatusSamplerTests {

    /// The first reading has nothing to compare against. It must still produce a usable
    /// snapshot — memory, disk and battery are absolute, not rates — while reporting no
    /// rates rather than inventing them.
    @Test("produces a snapshot on the very first sample, with no rates yet")
    func firstSample() {
        let probe = StubProbe()
        let sampler = StatusSampler(probe: probe, now: { Date(timeIntervalSince1970: 0) })

        let status = sampler.sample()

        #expect(status != nil)
        #expect(sampler.hasRates == false)
        #expect(status?.cpuPercent == 0)
        #expect(status?.memory.totalBytes == 16_000_000_000)
    }

    @Test("computes rates once a second reading arrives")
    func secondSample() {
        let probe = StubProbe()
        let clock = Mutex<Date>(Date(timeIntervalSince1970: 0))
        let sampler = StatusSampler(probe: probe, now: { clock.withLock { $0 } })

        _ = sampler.sample()

        clock.withLock { $0 = Date(timeIntervalSince1970: 2) }
        probe.ticks = CPUTicks(user: 100, system: 0, idle: 1100)
        probe.net = NetworkCounters(bytesReceived: 4000, bytesSent: 2000)

        let status = sampler.sample()

        #expect(sampler.hasRates)
        #expect(status?.cpuPercent == 50)
        #expect(status?.network.downloadBytesPerSecond == 2000)
    }

    /// A counter that is briefly unreadable should leave the last known figure on
    /// screen, not blink the dashboard to zero and back.
    @Test("holds the last known rate when a counter is momentarily unreadable")
    func holdsLastKnownRate() {
        let probe = StubProbe()
        let clock = Mutex<Date>(Date(timeIntervalSince1970: 0))
        let sampler = StatusSampler(probe: probe, now: { clock.withLock { $0 } })

        _ = sampler.sample()
        clock.withLock { $0 = Date(timeIntervalSince1970: 1) }
        // Totals must grow between samples; holding total constant means no elapsed
        // ticks and therefore no computable percentage at all.
        probe.ticks = CPUTicks(user: 50, system: 0, idle: 1050)
        _ = sampler.sample()

        clock.withLock { $0 = Date(timeIntervalSince1970: 2) }
        probe.ticks = nil
        let status = sampler.sample()

        #expect(status?.cpuPercent == 50)
    }

    /// Memory and disk are the dashboard's floor. Without them there is nothing worth
    /// showing, and zeroes would read as a machine in catastrophic trouble.
    @Test("returns nothing rather than a snapshot of zeroes when memory is unreadable")
    func refusesToInventZeroes() {
        let probe = StubProbe()
        probe.mem = nil
        let sampler = StatusSampler(probe: probe, now: { Date() })

        #expect(sampler.sample() == nil)
    }

    @Test("passes through the count of processes it was not allowed to read")
    func reportsUnreadableProcesses() {
        let probe = StubProbe()
        probe.unreadable = 236
        let sampler = StatusSampler(probe: probe, now: { Date() })

        #expect(sampler.sample()?.unreadableProcessCount == 236)
    }
}
