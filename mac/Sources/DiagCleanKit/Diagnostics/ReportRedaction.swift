import Foundation

/// Removes the things that identify a machine or its owner.
///
/// A diagnostic report routinely leaves the building: attached to a ticket, forwarded to
/// a vendor, pasted into a chat. Most of the time a technician wants the identifiers —
/// they are working a specific machine and the ticket needs to say which one. Sometimes
/// they are sending a report to a third party who has no business knowing whose laptop
/// it is, and then they want them gone.
///
/// So redaction is an explicit switch rather than a default, and it replaces values with
/// a visible marker instead of deleting the rows. A report with a blank network section
/// looks like a collection failure; one that says "redacted" says a person made a choice.
public enum ReportRedaction {
    public static let marker = "[redacted]"

    public static func apply(to report: DiagnosticReport) -> DiagnosticReport {
        DiagnosticReport(
            generatedAt: report.generatedAt,
            sections: report.sections,
            overview: report.overview.map(redact),
            hardware: report.hardware,
            volumes: report.volumes,
            performance: report.performance,
            interfaces: report.interfaces.map(redact),
            // An internal resolver address identifies the network the machine sits on,
            // which is exactly the kind of thing not to hand a third party.
            dnsServers: report.dnsServers.isEmpty ? [] : [marker],
            software: report.software,
            crashes: report.crashes,
            failures: report.failures
        )
    }

    private static func redact(_ overview: SystemOverview) -> SystemOverview {
        SystemOverview(
            computerName: marker,
            userName: marker,
            // The OS version and build stay: they identify the software, not the person,
            // and stripping them would gut the report's usefulness for no privacy gain.
            osVersion: overview.osVersion,
            osBuild: overview.osBuild,
            uptime: overview.uptime
        )
    }

    private static func redact(_ interface: NetworkInterfaceInfo) -> NetworkInterfaceInfo {
        NetworkInterfaceInfo(
            // The interface name (en0, utun3) describes the hardware, not the network,
            // so it survives; the addresses do not.
            name: interface.name,
            macAddress: interface.macAddress == nil ? nil : marker,
            ipAddresses: interface.ipAddresses.isEmpty ? [] : [marker],
            isUp: interface.isUp
        )
    }
}
