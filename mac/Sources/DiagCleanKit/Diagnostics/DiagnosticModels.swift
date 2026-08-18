import Foundation

/// The sections a report can contain. Each is independently includable, because a
/// diagnostic report is an information-disclosure surface before it is anything else:
/// it goes into a ticket, gets forwarded, and sometimes reaches a third-party vendor.
/// A technician should be able to send the disk health without also sending a complete
/// inventory of everything installed on somebody's laptop.
public enum ReportSection: String, CaseIterable, Sendable, Identifiable, Codable {
    case overview
    case hardware
    case storage
    case performance
    case network
    case software
    case crashes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .hardware: return "Hardware"
        case .storage: return "Storage"
        case .performance: return "Performance"
        case .network: return "Network"
        case .software: return "Installed Software"
        case .crashes: return "Recent Crashes"
        }
    }

    /// Says plainly what leaves the machine if this section is included. Written for the
    /// person deciding whether to attach the report, not for the developer.
    public var contents: String {
        switch self {
        case .overview: return "Computer name, macOS version, uptime, who generated the report"
        case .hardware: return "Model, chip, core count, installed memory"
        case .storage: return "Volumes, capacity, free space, SMART health"
        case .performance: return "Current CPU, memory and swap usage"
        case .network: return "Interface names, IP and MAC addresses, DNS servers"
        case .software: return "Every application installed, with version numbers"
        case .crashes: return "Names and dates of apps that crashed recently"
        }
    }

    /// Whether this section carries anything that identifies the machine or its owner.
    /// Drives the warning in the UI and what redaction touches.
    public var carriesIdentifiers: Bool {
        switch self {
        case .overview, .network: return true
        case .hardware, .storage, .performance, .software, .crashes: return false
        }
    }
}

public struct SystemOverview: Sendable, Equatable {
    public let computerName: String
    public let userName: String
    public let osVersion: String
    public let osBuild: String
    public let uptime: TimeInterval

    public init(computerName: String, userName: String, osVersion: String, osBuild: String, uptime: TimeInterval) {
        self.computerName = computerName
        self.userName = userName
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.uptime = uptime
    }
}

public struct HardwareInfo: Sendable, Equatable {
    public let model: String
    public let chip: String
    public let coreCount: Int
    public let memoryBytes: UInt64

    public init(model: String, chip: String, coreCount: Int, memoryBytes: UInt64) {
        self.model = model
        self.chip = chip
        self.coreCount = coreCount
        self.memoryBytes = memoryBytes
    }
}

public enum SmartStatus: String, Sendable, Equatable, Codable {
    case verified
    case failing
    case notSupported
    case unknown

    public var label: String {
        switch self {
        case .verified: return "Verified"
        case .failing: return "Failing"
        case .notSupported: return "Not supported"
        case .unknown: return "Unknown"
        }
    }

    /// The one thing in a diagnostic report that means "replace this machine now".
    public var isAlarming: Bool { self == .failing }
}

public struct VolumeInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let deviceIdentifier: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let isInternal: Bool
    public let smartStatus: SmartStatus

    public init(
        name: String, deviceIdentifier: String, totalBytes: Int64,
        availableBytes: Int64, isInternal: Bool, smartStatus: SmartStatus
    ) {
        self.id = deviceIdentifier.isEmpty ? name : deviceIdentifier
        self.name = name
        self.deviceIdentifier = deviceIdentifier
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.isInternal = isInternal
        self.smartStatus = smartStatus
    }
}

public struct NetworkInterfaceInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let macAddress: String?
    public let ipAddresses: [String]
    public let isUp: Bool

    public init(name: String, macAddress: String?, ipAddresses: [String], isUp: Bool) {
        self.id = name
        self.name = name
        self.macAddress = macAddress
        self.ipAddresses = ipAddresses
        self.isUp = isUp
    }
}

public struct CrashRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let appName: String
    public let date: Date

    public init(appName: String, date: Date, fileName: String) {
        self.id = fileName
        self.appName = appName
        self.date = date
    }
}

/// A collector that failed, recorded rather than allowed to abort the run. A partial
/// report a technician can still attach beats no report at all, and a silently missing
/// section is worse than one that says why it is missing.
public struct CollectorFailure: Sendable, Equatable, Identifiable {
    public let id: String
    public let section: ReportSection
    public let reason: String

    public init(section: ReportSection, reason: String) {
        self.id = section.rawValue
        self.section = section
        self.reason = reason
    }
}

public struct DiagnosticReport: Sendable {
    public let generatedAt: Date
    public let sections: Set<ReportSection>
    public let overview: SystemOverview?
    public let hardware: HardwareInfo?
    public let volumes: [VolumeInfo]
    public let performance: SystemStatus?
    public let interfaces: [NetworkInterfaceInfo]
    /// System-wide rather than per-interface, which is how macOS resolves them.
    public let dnsServers: [String]
    public let software: [InstalledApp]
    public let crashes: [CrashRecord]
    public let failures: [CollectorFailure]

    public init(
        generatedAt: Date, sections: Set<ReportSection>, overview: SystemOverview?,
        hardware: HardwareInfo?, volumes: [VolumeInfo], performance: SystemStatus?,
        interfaces: [NetworkInterfaceInfo], dnsServers: [String] = [],
        software: [InstalledApp], crashes: [CrashRecord], failures: [CollectorFailure]
    ) {
        self.generatedAt = generatedAt
        self.sections = sections
        self.overview = overview
        self.hardware = hardware
        self.volumes = volumes
        self.performance = performance
        self.interfaces = interfaces
        self.dnsServers = dnsServers
        self.software = software
        self.crashes = crashes
        self.failures = failures
    }

    public func includes(_ section: ReportSection) -> Bool { sections.contains(section) }
}
