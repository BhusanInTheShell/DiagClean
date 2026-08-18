import Foundation
import Testing
@testable import DiagCleanKit

private struct FailingCollector: DiagnosticCollecting {
    struct Boom: Error, LocalizedError {
        var errorDescription: String? { "Permission denied" }
    }

    var failing: Set<ReportSection>

    func overview() throws -> SystemOverview {
        if failing.contains(.overview) { throw Boom() }
        return SystemOverview(computerName: "Mac", userName: "Alex", osVersion: "15.0", osBuild: "24A", uptime: 10)
    }
    func hardware() throws -> HardwareInfo {
        if failing.contains(.hardware) { throw Boom() }
        return HardwareInfo(model: "Mac15,3", chip: "M3", coreCount: 8, memoryBytes: 16_000_000_000)
    }
    func volumes() throws -> [VolumeInfo] {
        if failing.contains(.storage) { throw Boom() }
        return [VolumeInfo(name: "Macintosh HD", deviceIdentifier: "/", totalBytes: 100,
                           availableBytes: 50, isInternal: true, smartStatus: .verified)]
    }
    func interfaces() throws -> [NetworkInterfaceInfo] {
        if failing.contains(.network) { throw Boom() }
        return [NetworkInterfaceInfo(name: "en0", macAddress: "aa", ipAddresses: ["10.0.0.1"], isUp: true)]
    }
    func dnsServers() throws -> [String] {
        if failing.contains(.network) { throw Boom() }
        return ["192.168.1.1"]
    }
    func crashes() throws -> [CrashRecord] {
        if failing.contains(.crashes) { throw Boom() }
        return []
    }
}

@Suite("DiagnosticService")
struct DiagnosticServiceTests {

    private func service(failing: Set<ReportSection> = []) -> DiagnosticService {
        DiagnosticService(
            collector: FailingCollector(failing: failing),
            lister: AppLister(roots: []),
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    /// A technician on somebody else's machine needs whatever report they can get. One
    /// collector hitting a permission wall must not cost them the other five sections.
    @Test("one failing collector does not abort the rest of the report")
    func failureIsIsolated() async {
        let report = await service(failing: [.storage])
            .generate(sections: [.overview, .hardware, .storage, .network])

        #expect(report.overview != nil)
        #expect(report.hardware != nil)
        #expect(report.interfaces.count == 1)
        #expect(report.volumes.isEmpty)
        #expect(report.failures.count == 1)
        #expect(report.failures[0].section == .storage)
        #expect(report.failures[0].reason == "Permission denied")
    }

    @Test("records every failure, not just the first")
    func recordsAllFailures() async {
        let report = await service(failing: [.storage, .network, .crashes])
            .generate(sections: Set(ReportSection.allCases).subtracting([.performance, .software]))

        #expect(report.failures.count == 3)
        #expect(Set(report.failures.map(\.section)) == [.storage, .network, .crashes])
    }

    /// Excluding a section must mean the data was never gathered, not gathered and then
    /// hidden. The difference matters when the reason for excluding it was that it
    /// should not exist in a file somebody might forward.
    @Test("does not collect a section that was not asked for")
    func doesNotCollectExcludedSections() async {
        let report = await service().generate(sections: [.hardware])

        #expect(report.hardware != nil)
        #expect(report.overview == nil)
        #expect(report.interfaces.isEmpty)
        #expect(report.volumes.isEmpty)
    }

    @Test("a section that was not requested cannot fail")
    func excludedSectionsProduceNoFailures() async {
        let report = await service(failing: [.storage, .network]).generate(sections: [.hardware])

        #expect(report.failures.isEmpty)
    }

    /// Network gathers both interfaces and DNS, so a network failure reaches the
    /// recorder twice. Listing the section twice reads as two separate problems.
    @Test("reports one failure per section even when several collectors back it")
    func deduplicatesFailuresPerSection() async {
        let report = await service(failing: [.network]).generate(sections: [.network])

        #expect(report.failures.count == 1)
    }

    @Test("carries the requested section set into the report")
    func recordsRequestedSections() async {
        let requested: Set<ReportSection> = [.hardware, .storage]
        let report = await service().generate(sections: requested)

        #expect(report.sections == requested)
        #expect(report.includes(.hardware))
        #expect(!report.includes(.network))
    }

    @Test("an empty selection produces an empty report rather than an error")
    func emptySelection() async {
        let report = await service().generate(sections: [])

        #expect(report.overview == nil)
        #expect(report.failures.isEmpty)
        #expect(!HTMLReportBuilder.build(report).isEmpty)
    }
}
