import Foundation

/// Assembles a report from the collectors.
///
/// Every collector runs in isolation. One failing — a permission macOS declined, a
/// command that is not there, a volume that vanished mid-scan — is recorded against its
/// section rather than aborting the run. A technician on someone else's machine needs
/// the report they can get, and a section that explains why it is missing is far better
/// than one that silently is not there.
public struct DiagnosticService: Sendable {
    private let collector: DiagnosticCollecting
    private let lister: AppLister
    private let sampler: StatusSampler
    private let now: @Sendable () -> Date

    public init(
        collector: DiagnosticCollecting = LiveDiagnosticCollector(),
        lister: AppLister = AppLister(),
        sampler: StatusSampler = StatusSampler(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.collector = collector
        self.lister = lister
        self.sampler = sampler
        self.now = now
    }

    /// - Parameter sections: only these are collected. Excluding a section means the
    ///   data is never gathered at all, not gathered and then hidden — the difference
    ///   matters when the reason for excluding it was that it should not exist in a file
    ///   somebody might forward.
    public func generate(sections: Set<ReportSection>) async -> DiagnosticReport {
        var failures: [CollectorFailure] = []

        let overview = collect(.overview, in: sections, &failures) { try collector.overview() }
        let hardware = collect(.hardware, in: sections, &failures) { try collector.hardware() }
        let volumes = collect(.storage, in: sections, &failures) { try collector.volumes() } ?? []
        let interfaces = collect(.network, in: sections, &failures) { try collector.interfaces() } ?? []
        let dns = collect(.network, in: sections, &failures) { try collector.dnsServers() } ?? []
        let crashes = collect(.crashes, in: sections, &failures) { try collector.crashes() } ?? []

        var performance: SystemStatus?
        if sections.contains(.performance) {
            // Two samples a second apart: the first has no predecessor to compare
            // against, so a single reading would report 0% CPU on every report.
            _ = sampler.sample()
            try? await Task.sleep(for: .seconds(1))
            performance = sampler.sample()
            if performance == nil {
                failures.append(CollectorFailure(
                    section: .performance, reason: "System counters could not be read."
                ))
            }
        }

        var software: [InstalledApp] = []
        if sections.contains(.software) {
            do {
                software = try await lister.listApps()
            } catch {
                failures.append(CollectorFailure(
                    section: .software, reason: (error as NSError).localizedDescription
                ))
            }
        }

        // One section can have more than one collector behind it — Network gathers both
        // interfaces and DNS — and listing the same section twice in "could not be
        // collected" reads like two separate problems rather than one.
        var seen = Set<ReportSection>()
        let deduplicated = failures.filter { seen.insert($0.section).inserted }

        return DiagnosticReport(
            generatedAt: now(),
            sections: sections,
            overview: overview,
            hardware: hardware,
            volumes: volumes,
            performance: performance,
            interfaces: interfaces,
            dnsServers: dns,
            software: software,
            crashes: crashes,
            failures: deduplicated
        )
    }

    private func collect<T>(
        _ section: ReportSection,
        in sections: Set<ReportSection>,
        _ failures: inout [CollectorFailure],
        _ work: () throws -> T
    ) -> T? {
        guard sections.contains(section) else { return nil }
        do {
            return try work()
        } catch {
            failures.append(CollectorFailure(
                section: section, reason: (error as NSError).localizedDescription
            ))
            return nil
        }
    }
}
