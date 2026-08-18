import Foundation
import Darwin

/// Gathers the facts a report is built from.
///
/// Reuses what the rest of the app already has: `LiveSystemProbe` for live counters and
/// `AppLister` for the software inventory. Those are already native and already tested,
/// and a second implementation of either would be a second thing to keep honest.
public protocol DiagnosticCollecting: Sendable {
    func overview() throws -> SystemOverview
    func hardware() throws -> HardwareInfo
    func volumes() throws -> [VolumeInfo]
    func interfaces() throws -> [NetworkInterfaceInfo]
    func dnsServers() throws -> [String]
    func crashes() throws -> [CrashRecord]
}

public struct LiveDiagnosticCollector: DiagnosticCollecting {
    private let probe: SystemProbing

    public init(probe: SystemProbing = LiveSystemProbe()) {
        self.probe = probe
    }

    // MARK: Overview

    public func overview() throws -> SystemOverview {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SystemOverview(
            computerName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            userName: NSFullUserName(),
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            osBuild: sysctlString("kern.osversion") ?? "",
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    // MARK: Hardware

    public func hardware() throws -> HardwareInfo {
        HardwareInfo(
            model: sysctlString("hw.model") ?? "Unknown",
            chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown",
            coreCount: ProcessInfo.processInfo.processorCount,
            memoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    // MARK: Storage

    public func volumes() throws -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
        ]
        guard let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else { return [] }

        // SMART status is read once for the whole machine rather than per volume: the
        // several APFS volumes on a modern Mac all live on one physical device, so
        // asking per volume would run `diskutil` five times for one answer.
        let smart = smartStatusForBootDisk()

        return mounted.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let isInternal = values.volumeIsInternal ?? false

            return VolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                deviceIdentifier: url.path,
                totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                availableBytes: Int64(values.volumeAvailableCapacityForImportantUsage ?? 0),
                isInternal: isInternal,
                // SMART is a property of physical media; an external or network volume
                // reports whatever it reports, and claiming the boot disk's verdict for
                // it would be a fabrication.
                smartStatus: isInternal ? smart : .unknown
            )
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// The one place this file shells out. macOS exposes no public API for SMART status,
    /// and "is this disk dying" is the single most valuable line in a diagnostic report,
    /// so `diskutil` is worth the subprocess. Everything else here is a syscall.
    private func smartStatusForBootDisk() -> SmartStatus {
        guard let output = runCommand("/usr/sbin/diskutil", ["info", "/"]) else { return .unknown }

        for line in output.split(separator: "\n") {
            guard line.contains("SMART Status") else { continue }
            let value = line.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces).lowercased() ?? ""

            if value.contains("verified") { return .verified }
            if value.contains("failing") { return .failing }
            if value.contains("not supported") { return .notSupported }
        }
        return .unknown
    }

    // MARK: Network

    public func interfaces() throws -> [NetworkInterfaceInfo] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }

        var ipsByInterface: [String: [String]] = [:]
        var macByInterface: [String: String] = [:]
        var upInterfaces: Set<String> = []

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo"), let addr = current.pointee.ifa_addr else { continue }

            if current.pointee.ifa_flags & UInt32(IFF_UP) != 0 {
                upInterfaces.insert(name)
            }

            switch Int32(addr.pointee.sa_family) {
            case AF_INET, AF_INET6:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                    nil, 0, NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: host)
                    // Link-local IPv6 carries a scope suffix and no diagnostic value.
                    if !ip.hasPrefix("fe80") {
                        ipsByInterface[name, default: []].append(ip)
                    }
                }
            case AF_LINK:
                if let mac = macAddress(from: addr) {
                    macByInterface[name] = mac
                }
            default:
                break
            }
        }

        return Set(ipsByInterface.keys).union(macByInterface.keys)
            .sorted()
            .map { name in
                NetworkInterfaceInfo(
                    name: name,
                    macAddress: macByInterface[name],
                    ipAddresses: ipsByInterface[name] ?? [],
                    isUp: upInterfaces.contains(name)
                )
            }
            // Interfaces with neither an address nor a link layer tell a technician
            // nothing and would pad the report with dozens of empty rows.
            .filter { !$0.ipAddresses.isEmpty || $0.macAddress != nil }
    }

    /// Read from `/etc/resolv.conf`, which is what the resolver actually consults.
    /// System-wide rather than per-interface: macOS resolves against one list regardless
    /// of which interface carried the packet.
    public func dnsServers() throws -> [String] {
        guard let contents = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else {
            return []
        }
        return contents
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2, parts[0] == "nameserver" else { return nil }
                return String(parts[1])
            }
    }

    private func macAddress(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl -> String? in
            guard dl.pointee.sdl_alen == 6 else { return nil }
            let base = UnsafeRawPointer(dl).advanced(by: 8 + Int(dl.pointee.sdl_nlen))
                .assumingMemoryBound(to: UInt8.self)
            return (0..<6).map { String(format: "%02x", base[$0]) }.joined(separator: ":")
        }
    }

    // MARK: Crashes

    /// Reads the crash-report directories rather than querying the unified log.
    ///
    /// `log show` takes tens of seconds and returns mostly noise; the filenames in
    /// DiagnosticReports are already exactly what a technician wants to know — what
    /// crashed, and when. Faster, and more useful for the question actually being asked.
    public func crashes() throws -> [CrashRecord] {
        let directories = [
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/DiagnosticReports"),
            "/Library/Logs/DiagnosticReports",
        ]
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        var records: [CrashRecord] = []

        for directory in directories {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for file in contents {
                guard file.hasSuffix(".ips") || file.hasSuffix(".crash") || file.hasSuffix(".hang") else { continue }

                let path = (directory as NSString).appendingPathComponent(file)
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                let date = (attributes?[.creationDate] as? Date) ?? Date.distantPast
                guard date > cutoff else { continue }

                // Crash filenames are "AppName-2026-08-18-120000.ips"; everything from
                // the first date-looking component onwards is metadata, not a name.
                let appName = file.split(separator: "-").first.map(String.init) ?? file
                records.append(CrashRecord(appName: appName, date: date, fileName: file))
            }
        }

        return records.sorted { $0.date > $1.date }
    }

    // MARK: Helpers

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        // sysctl returns a null-terminated string; the terminator has to come off
        // before decoding or it lands in the middle of the report as a stray character.
        let bytes = buffer.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runCommand(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
