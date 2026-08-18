import Foundation
import Testing
@testable import DiagCleanKit

/// Reading a counter is easy. Subtracting two of them correctly — when one has wrapped,
/// when no time has passed, when a process did not exist a moment ago — is where a live
/// dashboard starts reporting 4000% CPU or a negative download rate. That arithmetic is
/// what these tests pin down.
@Suite("StatusCalculator")
struct StatusCalculatorTests {

    private func ticks(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    // MARK: - CPU

    @Test("computes busy percentage between two tick samples")
    func cpuPercent() {
        let before = ticks(user: 100, system: 50, idle: 850)
        // 100 more busy ticks out of 200 elapsed.
        let after = ticks(user: 180, system: 70, idle: 950)

        #expect(StatusCalculator.cpuPercent(from: before, to: after) == 50)
    }

    @Test("reports a fully idle machine as zero, not as nothing")
    func cpuIdle() {
        let before = ticks(user: 100, system: 50, idle: 850)
        let after = ticks(user: 100, system: 50, idle: 950)

        #expect(StatusCalculator.cpuPercent(from: before, to: after) == 0)
    }

    /// Two identical samples carry no information about the interval between them. A
    /// dashboard blank for one refresh is honest; a fabricated 0% is not.
    @Test("returns nothing when no ticks have elapsed")
    func cpuNoElapsedTicks() {
        let sample = ticks(user: 100, system: 50, idle: 850)

        #expect(StatusCalculator.cpuPercent(from: sample, to: sample) == nil)
    }

    @Test("returns nothing when the counters have gone backwards")
    func cpuCounterReset() {
        let before = ticks(user: 500, system: 500, idle: 5000)
        let after = ticks(user: 10, system: 10, idle: 100)

        #expect(StatusCalculator.cpuPercent(from: before, to: after) == nil)
    }

    @Test("never reports more than 100 percent")
    func cpuClamped() {
        let before = ticks(user: 0, system: 0, idle: 1000)
        // Busy grows faster than total, which should be impossible but must not escape
        // as a percentage nobody can act on.
        let after = ticks(user: 5000, system: 0, idle: 1000)

        let percent = try? #require(StatusCalculator.cpuPercent(from: before, to: after))
        #expect((percent ?? 0) <= 100)
    }

    // MARK: - Network

    @Test("computes byte rates over the elapsed interval")
    func networkRates() {
        let before = NetworkCounters(bytesReceived: 1000, bytesSent: 500)
        let after = NetworkCounters(bytesReceived: 3000, bytesSent: 1500)

        let rates = StatusCalculator.networkRates(from: before, to: after, interval: 2)

        #expect(rates?.downloadBytesPerSecond == 1000)
        #expect(rates?.uploadBytesPerSecond == 500)
    }

    /// Interface counters reset when an interface drops and returns, which happens all
    /// day on a laptop moving between networks. That must not surface as a negative rate.
    @Test("returns nothing when an interface counter has reset")
    func networkCounterReset() {
        let before = NetworkCounters(bytesReceived: 10_000, bytesSent: 10_000)
        let after = NetworkCounters(bytesReceived: 5, bytesSent: 5)

        #expect(StatusCalculator.networkRates(from: before, to: after, interval: 2) == nil)
    }

    @Test("returns nothing when no time has passed")
    func networkZeroInterval() {
        let before = NetworkCounters(bytesReceived: 1000, bytesSent: 500)
        let after = NetworkCounters(bytesReceived: 3000, bytesSent: 1500)

        #expect(StatusCalculator.networkRates(from: before, to: after, interval: 0) == nil)
    }

    // MARK: - Processes

    @Test("computes per-process CPU as a share of one core, matching Activity Monitor")
    func processPercent() {
        let before = [ProcessSample(pid: 1, name: "busy", cpuNanoseconds: 0, residentBytes: 0)]
        // One full second of CPU over one second of wall time is 100% of a core.
        let after = [ProcessSample(pid: 1, name: "busy", cpuNanoseconds: 1_000_000_000, residentBytes: 0)]

        let usage = StatusCalculator.processUsage(from: before, to: after, interval: 1)

        #expect(usage.count == 1)
        #expect(usage[0].cpuPercent == 100)
    }

    /// Crediting a newly-launched process with every nanosecond it has ever used is how
    /// a status view ends up claiming a just-opened app is running at 900%.
    @Test("skips a process that did not exist in the earlier sample")
    func processNewlyLaunched() {
        let before: [ProcessSample] = []
        let after = [ProcessSample(pid: 42, name: "fresh", cpuNanoseconds: 9_000_000_000, residentBytes: 0)]

        #expect(StatusCalculator.processUsage(from: before, to: after, interval: 1).isEmpty)
    }

    @Test("skips a process whose CPU counter went backwards")
    func processCounterWentBackwards() {
        let before = [ProcessSample(pid: 7, name: "odd", cpuNanoseconds: 5_000_000_000, residentBytes: 0)]
        let after = [ProcessSample(pid: 7, name: "odd", cpuNanoseconds: 1_000_000_000, residentBytes: 0)]

        #expect(StatusCalculator.processUsage(from: before, to: after, interval: 1).isEmpty)
    }

    @Test("orders by CPU and keeps only the requested number")
    func processOrderingAndLimit() {
        let before = (1...5).map { ProcessSample(pid: Int32($0), name: "p\($0)", cpuNanoseconds: 0, residentBytes: 0) }
        let after = (1...5).map {
            ProcessSample(pid: Int32($0), name: "p\($0)", cpuNanoseconds: UInt64($0) * 100_000_000, residentBytes: 0)
        }

        let usage = StatusCalculator.processUsage(from: before, to: after, interval: 1, limit: 3)

        #expect(usage.map(\.name) == ["p5", "p4", "p3"])
    }

    @Test("drops processes using a negligible slice of CPU")
    func processDropsNoise() {
        let before = [ProcessSample(pid: 1, name: "idle", cpuNanoseconds: 0, residentBytes: 0)]
        let after = [ProcessSample(pid: 1, name: "idle", cpuNanoseconds: 100_000, residentBytes: 0)]

        #expect(StatusCalculator.processUsage(from: before, to: after, interval: 1).isEmpty)
    }

    // MARK: - Verdicts

    @Test("grades CPU load")
    func cpuHealth() {
        #expect(StatusCalculator.cpuHealth(percent: 12) == .normal)
        #expect(StatusCalculator.cpuHealth(percent: 75) == .elevated)
        #expect(StatusCalculator.cpuHealth(percent: 96) == .critical)
    }

    /// A healthy Mac routinely sits above 80% memory used, because unused RAM is wasted
    /// RAM. macOS's own pressure verdict is the signal that actually means something.
    @Test("trusts macOS's memory pressure over raw used-percentage")
    func memoryPrefersPressure() {
        let busyButHappy = MemorySample(
            totalBytes: 16_000_000_000, usedBytes: 15_000_000_000,
            swapUsedBytes: 0, pressureLevel: .normal
        )

        #expect(StatusCalculator.memoryHealth(busyButHappy) == .normal)
    }

    @Test("falls back to used-percentage when pressure is unreadable")
    func memoryFallsBack() {
        let sample = MemorySample(
            totalBytes: 16_000_000_000, usedBytes: 15_400_000_000,
            swapUsedBytes: 0, pressureLevel: nil
        )

        #expect(StatusCalculator.memoryHealth(sample) == .critical)
    }

    /// Neither proportion nor absolute size is sufficient alone: a 4 TB disk at 95% has
    /// 200 GB free and is fine, a 128 GB disk at 92% has 10 GB and is not.
    @Test("grades disk space on both proportion and absolute free space")
    func diskHealth() {
        let bigDiskMostlyFull = DiskSpaceSample(
            totalBytes: 4_000_000_000_000, availableBytes: 200_000_000_000, purgeableBytes: 0
        )
        #expect(StatusCalculator.diskHealth(bigDiskMostlyFull) == .normal)

        let smallDiskNearlyFull = DiskSpaceSample(
            totalBytes: 128_000_000_000, availableBytes: 10_000_000_000, purgeableBytes: 0
        )
        #expect(StatusCalculator.diskHealth(smallDiskNearlyFull) == .elevated)

        let almostGone = DiskSpaceSample(
            totalBytes: 128_000_000_000, availableBytes: 2_000_000_000, purgeableBytes: 0
        )
        #expect(StatusCalculator.diskHealth(almostGone) == .critical)
    }

    /// Plugged in at 8% is a machine charging, not a machine in trouble.
    @Test("only grades battery while running on battery")
    func batteryHealth() {
        let lowButCharging = BatterySample(
            percent: 8, isCharging: true, isPluggedIn: true,
            minutesRemaining: nil, cycleCount: nil, healthPercent: nil
        )
        #expect(StatusCalculator.batteryHealth(lowButCharging) == .normal)

        let lowOnBattery = BatterySample(
            percent: 8, isCharging: false, isPluggedIn: false,
            minutesRemaining: 12, cycleCount: nil, healthPercent: nil
        )
        #expect(StatusCalculator.batteryHealth(lowOnBattery) == .critical)
    }

    @Test("overall health is the worst of the parts")
    func overallHealth() {
        let status = SystemStatus(
            cpuPercent: 5, coreCount: 8, loadAverage: nil,
            memory: MemorySample(totalBytes: 16_000_000_000, usedBytes: 4_000_000_000,
                                 swapUsedBytes: 0, pressureLevel: .normal),
            disk: DiskSpaceSample(totalBytes: 128_000_000_000, availableBytes: 1_000_000_000, purgeableBytes: 0),
            network: .zero, battery: nil, uptime: 100,
            topProcesses: [], unreadableProcessCount: 0, sampledAt: Date()
        )

        #expect(StatusCalculator.overallHealth(status) == .critical)
    }
}
