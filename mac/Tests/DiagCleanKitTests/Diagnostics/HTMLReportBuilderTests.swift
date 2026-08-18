import Foundation
import Testing
@testable import DiagCleanKit

private func report(
    sections: Set<ReportSection> = Set(ReportSection.allCases),
    overview: SystemOverview? = SystemOverview(
        computerName: "Test Mac", userName: "Alex Doe",
        osVersion: "15.0", osBuild: "24A335", uptime: 90_000
    ),
    volumes: [VolumeInfo] = [],
    interfaces: [NetworkInterfaceInfo] = [],
    dnsServers: [String] = [],
    software: [InstalledApp] = [],
    crashes: [CrashRecord] = [],
    failures: [CollectorFailure] = []
) -> DiagnosticReport {
    DiagnosticReport(
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        sections: sections, overview: overview,
        hardware: HardwareInfo(model: "Mac15,3", chip: "Apple M3", coreCount: 8, memoryBytes: 16_000_000_000),
        volumes: volumes, performance: nil, interfaces: interfaces,
        dnsServers: dnsServers, software: software, crashes: crashes, failures: failures
    )
}

@Suite("HTMLReportBuilder")
struct HTMLReportBuilderTests {

    // MARK: - Escaping

    /// Names in a report are not all chosen by the person reading it. Somebody can
    /// install an app called `<script>` or name a disk with a quote, and this document is
    /// built by string concatenation and then opened in a browser.
    @Test("escapes markup in application names")
    func escapesApplicationNames() {
        let hostile = InstalledApp(
            path: "/Applications/x.app",
            name: "<script>alert('xss')</script>",
            bundleIdentifier: "com.example.x", version: "1.0",
            sizeBytes: 1024, lastUsed: nil, isAppleSoftware: false
        )

        let html = HTMLReportBuilder.build(report(software: [hostile]))

        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test("escapes markup in the computer name")
    func escapesComputerName() {
        let overview = SystemOverview(
            computerName: "<img src=x onerror=alert(1)>", userName: "Alex",
            osVersion: "15.0", osBuild: "24A335", uptime: 100
        )

        let html = HTMLReportBuilder.build(report(overview: overview))

        #expect(!html.contains("<img src=x"))
        #expect(html.contains("&lt;img"))
    }

    @Test("escapes quotes and ampersands")
    func escapesQuotesAndAmpersands() {
        #expect(HTMLReportBuilder.escape("Tom & \"Jerry\"") == "Tom &amp; &quot;Jerry&quot;")
        #expect(HTMLReportBuilder.escape("it's") == "it&#39;s")
    }

    /// The separator between addresses has to be real markup, so each address is escaped
    /// on its own. Escaping the joined string prints a literal "<br>" on the page.
    @Test("joins multiple addresses with real line breaks, not escaped ones")
    func joinsAddressesWithMarkup() {
        let interface = NetworkInterfaceInfo(
            name: "en0", macAddress: "aa:bb:cc:dd:ee:ff",
            ipAddresses: ["192.168.1.10", "10.0.0.5"], isUp: true
        )

        let html = HTMLReportBuilder.build(report(interfaces: [interface]))

        #expect(html.contains("192.168.1.10<br>10.0.0.5"))
        #expect(!html.contains("&lt;br&gt;"))
    }

    // MARK: - Section selection

    /// Excluding a section has to actually keep the data out of the file. A report that
    /// merely hides it would still carry it to whoever the file is forwarded to.
    @Test("omits an excluded section's data entirely")
    func omitsExcludedSections() {
        let app = InstalledApp(
            path: "/Applications/Secret.app", name: "SecretInternalTool",
            bundleIdentifier: "com.example.secret", version: "1.0",
            sizeBytes: 1024, lastUsed: nil, isAppleSoftware: false
        )

        let withSoftware = HTMLReportBuilder.build(
            report(sections: [.software], software: [app])
        )
        let withoutSoftware = HTMLReportBuilder.build(
            report(sections: [.hardware], software: [app])
        )

        #expect(withSoftware.contains("SecretInternalTool"))
        #expect(!withoutSoftware.contains("SecretInternalTool"))
    }

    @Test("renders a failed collector as a stated reason rather than a silent gap")
    func rendersFailures() {
        let html = HTMLReportBuilder.build(report(
            failures: [CollectorFailure(section: .storage, reason: "Permission denied")]
        ))

        #expect(html.contains("Could not be collected"))
        #expect(html.contains("Permission denied"))
    }

    /// The one line in a diagnostic report that means "replace this machine now".
    @Test("marks a failing disk distinctly")
    func marksFailingDisk() {
        let failing = VolumeInfo(
            name: "Macintosh HD", deviceIdentifier: "/", totalBytes: 500_000_000_000,
            availableBytes: 100_000_000_000, isInternal: true, smartStatus: .failing
        )

        let html = HTMLReportBuilder.build(report(volumes: [failing]))

        #expect(html.contains("class=\"bad\""))
        #expect(html.contains("Failing"))
    }

    @Test("is a self-contained document with no external references")
    func isSelfContained() {
        let html = HTMLReportBuilder.build(report())

        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<style>"))
        // Emailed, dropped into a ticket, opened years later on a machine with no
        // network — none of which works if it reaches out for assets.
        #expect(!html.contains("src=\"http"))
        #expect(!html.contains("<link"))
        #expect(!html.contains("<script"))
    }
}

@Suite("ReportRedaction")
struct ReportRedactionTests {

    @Test("removes the computer name and the user's name")
    func redactsOverview() {
        let redacted = ReportRedaction.apply(to: report())

        #expect(redacted.overview?.computerName == ReportRedaction.marker)
        #expect(redacted.overview?.userName == ReportRedaction.marker)
    }

    /// Stripping the OS version would gut the report's usefulness and protect nobody:
    /// it identifies the software, not the person.
    @Test("keeps the macOS version and build")
    func keepsOSVersion() {
        let redacted = ReportRedaction.apply(to: report())

        #expect(redacted.overview?.osVersion == "15.0")
        #expect(redacted.overview?.osBuild == "24A335")
    }

    @Test("removes IP and MAC addresses but keeps the interface name")
    func redactsNetwork() {
        let interface = NetworkInterfaceInfo(
            name: "en0", macAddress: "aa:bb:cc:dd:ee:ff",
            ipAddresses: ["192.168.1.10"], isUp: true
        )

        let redacted = ReportRedaction.apply(to: report(interfaces: [interface]))

        #expect(redacted.interfaces[0].name == "en0")
        #expect(redacted.interfaces[0].macAddress == ReportRedaction.marker)
        #expect(redacted.interfaces[0].ipAddresses == [ReportRedaction.marker])
    }

    @Test("an interface with no MAC address does not gain one")
    func doesNotInventRedactedValues() {
        let interface = NetworkInterfaceInfo(name: "utun0", macAddress: nil, ipAddresses: [], isUp: true)

        let redacted = ReportRedaction.apply(to: report(interfaces: [interface]))

        #expect(redacted.interfaces[0].macAddress == nil)
        #expect(redacted.interfaces[0].ipAddresses.isEmpty)
    }

    /// A reader who does not know the report was redacted will read "[redacted]" as a
    /// collection failure, so the document says so at the top.
    @Test("the rendered report states that it was redacted")
    func rendersRedactionNotice() {
        let html = HTMLReportBuilder.build(report(), redacted: true)

        #expect(html.contains("redacted"))
        #expect(!html.contains("Test Mac"))
    }

    @Test("removes DNS servers, which identify the network the machine sits on")
    func redactsDNS() {
        let redacted = ReportRedaction.apply(to: report(dnsServers: ["10.1.1.1", "10.1.1.2"]))

        #expect(redacted.dnsServers == [ReportRedaction.marker])
    }

    @Test("hardware and storage survive redaction untouched")
    func keepsNonIdentifyingData() {
        let volume = VolumeInfo(
            name: "Macintosh HD", deviceIdentifier: "/", totalBytes: 500_000_000_000,
            availableBytes: 100_000_000_000, isInternal: true, smartStatus: .verified
        )

        let redacted = ReportRedaction.apply(to: report(volumes: [volume]))

        #expect(redacted.hardware?.chip == "Apple M3")
        #expect(redacted.volumes[0].name == "Macintosh HD")
    }
}
