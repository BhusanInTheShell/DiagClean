import Foundation
import Darwin
import IOKit.ps

/// Reads the machine's live counters.
///
/// Every metric comes from a direct system call rather than by spawning a command and
/// parsing its table. The CLI runs `iostat`, `vm_stat`, `pmset`, `netstat` and `ps` for
/// a single reading; a dashboard refreshing every couple of seconds would be launching
/// five processes a tick all day, and parsing a human-readable table is a format that
/// can change under you. These calls are what those tools themselves use.
public protocol SystemProbing: Sendable {
    func cpuTicks() -> CPUTicks?
    func coreCount() -> Int
    func loadAverage() -> LoadAverage?
    func memory() -> MemorySample?
    func diskSpace() -> DiskSpaceSample?
    func networkCounters() -> NetworkCounters?
    func battery() -> BatterySample?
    func uptime() -> TimeInterval
    /// Cumulative CPU time per process, plus the number macOS refused to report.
    func processes() -> (samples: [ProcessSample], unreadable: Int)
}

public struct LiveSystemProbe: SystemProbing {
    public init() {}

    // MARK: CPU

    public func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = UInt32(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    public func coreCount() -> Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    public func loadAverage() -> LoadAverage? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return nil }
        return LoadAverage(oneMinute: loads[0], fiveMinutes: loads[1], fifteenMinutes: loads[2])
    }

    // MARK: Memory

    public func memory() -> MemorySample? {
        guard let total = sysctlValue(UInt64.self, "hw.memsize"), total > 0 else { return nil }

        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // Active + wired + compressed, the same proxy the CLI uses. Inactive and
        // speculative pages are excluded: macOS keeps them full on purpose and counting
        // them would report a healthy machine as permanently out of memory.
        // Read via sysctl rather than the `vm_kernel_page_size` global, which Swift 6
        // rightly treats as shared mutable state. The vm_statistics64 counts are in
        // units of this page size, so getting it wrong scales every memory figure.
        guard let pageSize = sysctlValue(UInt32.self, "hw.pagesize").map(UInt64.init), pageSize > 0 else {
            return nil
        }
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * pageSize

        var swapUsed: UInt64 = 0
        if let swap = sysctlValue(xsw_usage.self, "vm.swapusage") {
            swapUsed = swap.xsu_used
        }

        return MemorySample(
            totalBytes: total,
            usedBytes: used,
            swapUsedBytes: swapUsed,
            pressureLevel: memoryPressure()
        )
    }

    /// macOS's own verdict, which is what Activity Monitor's pressure graph reflects.
    private func memoryPressure() -> HealthLevel? {
        guard let raw = sysctlValue(Int32.self, "kern.memorystatus_vm_pressure_level") else { return nil }
        switch raw {
        case 1: return .normal
        case 2: return .elevated
        case 4: return .critical
        default: return nil
        }
    }

    // MARK: Disk

    public func diskSpace() -> DiskSpaceSample? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else { return nil }

        guard let total = values.volumeTotalCapacity else { return nil }

        // The "important usage" figure is what Finder and System Settings show, because
        // it counts space macOS can reclaim on demand. Measured on a real machine the
        // two differed by 4 GB — reporting the raw number instead, as the CLI does,
        // means disagreeing with every other number the user can see.
        let important = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let raw = Int64(values.volumeAvailableCapacity ?? 0)

        return DiskSpaceSample(
            totalBytes: Int64(total),
            availableBytes: important > 0 ? important : raw,
            purgeableBytes: max(0, important - raw)
        )
    }

    // MARK: Network

    public func networkCounters() -> NetworkCounters? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = current.pointee.ifa_data else { continue }

            // Loopback carries the machine talking to itself, which is not throughput
            // anybody means when they ask what the network is doing.
            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }

        return NetworkCounters(bytesReceived: received, bytesSent: sent)
    }

    // MARK: Battery

    public func battery() -> BatterySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let isPluggedIn = state == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            // macOS reports −1 while it is still working out an estimate. That is not a
            // duration, so it is reported as "unknown" rather than as a number.
            let rawMinutes = description[isPluggedIn ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            let minutes = (rawMinutes ?? -1) >= 0 ? rawMinutes : nil

            return BatterySample(
                percent: Int(Double(current) / Double(max) * 100),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesRemaining: minutes,
                cycleCount: description["Cycle Count"] as? Int,
                healthPercent: nil
            )
        }

        // No battery at all, which is simply what a desktop looks like.
        return nil
    }

    // MARK: Uptime

    public func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: Processes

    public func processes() -> (samples: [ProcessSample], unreadable: Int) {
        var pids = [pid_t](repeating: 0, count: 8192)
        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard byteCount > 0 else { return ([], 0) }

        let count = Int(byteCount) / MemoryLayout<pid_t>.size
        var samples: [ProcessSample] = []
        var unreadable = 0

        for index in 0..<count where pids[index] > 0 {
            let pid = pids[index]
            var info = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))

            // macOS refuses task info for processes owned by another user unless the
            // caller is root. On a normal machine that is roughly 40% of them, all
            // system daemons. Counting them is the honest alternative to a list that
            // silently omits whatever is actually busy.
            guard size == Int32(MemoryLayout<proc_taskinfo>.size) else {
                unreadable += 1
                continue
            }

            var nameBuffer = [CChar](repeating: 0, count: 4096)
            proc_name(pid, &nameBuffer, 4096)
            let name = String(cString: nameBuffer)

            samples.append(ProcessSample(
                pid: pid,
                name: name.isEmpty ? "pid \(pid)" : name,
                cpuNanoseconds: info.pti_total_user &+ info.pti_total_system,
                residentBytes: info.pti_resident_size
            ))
        }

        return (samples, unreadable)
    }

    // MARK: Helpers

    private func sysctlValue<T>(_ type: T.Type, _ name: String) -> T? {
        var size = MemoryLayout<T>.size
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }

        guard sysctlbyname(name, pointer, &size, nil, 0) == 0 else { return nil }
        return pointer.pointee
    }
}
