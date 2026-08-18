import Foundation
import Observation
import AppKit
import DiagCleanKit

@MainActor
@Observable
final class DiagnosticsViewModel {
    enum Phase {
        case configuring
        case generating
        case ready
    }

    private(set) var phase: Phase = .configuring
    private(set) var report: DiagnosticReport?
    private(set) var html: String = ""
    private(set) var errorMessage: String?
    private(set) var savedURL: URL?

    /// Everything on by default: a technician generating a report for their own ticket
    /// wants the whole picture, and having to tick six boxes before every report would
    /// make the safe path the tedious one.
    var selectedSections: Set<ReportSection> = Set(ReportSection.allCases)

    /// Off by default, and deliberately so. Most reports go into the reporter's own
    /// ticket for a machine they are already working on, where stripping the computer
    /// name just makes the report harder to use. It matters when the report is going
    /// somewhere else, which is the moment the switch is for.
    var redactIdentifiers = false

    private let service = DiagnosticService()
    private var generateTask: Task<Void, Never>?

    var sectionsCarryingIdentifiers: [ReportSection] {
        ReportSection.allCases.filter { selectedSections.contains($0) && $0.carriesIdentifiers }
    }

    var canGenerate: Bool { !selectedSections.isEmpty && phase != .generating }

    func toggle(_ section: ReportSection) {
        if selectedSections.contains(section) {
            selectedSections.remove(section)
        } else {
            selectedSections.insert(section)
        }
    }

    func generate() {
        guard canGenerate else { return }
        generateTask?.cancel()
        phase = .generating
        errorMessage = nil
        savedURL = nil

        generateTask = Task { [service, selectedSections, redactIdentifiers] in
            let result = await service.generate(sections: selectedSections)
            guard !Task.isCancelled else { return }

            self.report = result
            self.html = HTMLReportBuilder.build(result, redacted: redactIdentifiers)
            self.phase = .ready
        }
    }

    func startOver() {
        report = nil
        html = ""
        savedURL = nil
        errorMessage = nil
        phase = .configuring
    }

    // MARK: - Saving

    /// The report is written where the technician chooses and nowhere else. Nothing here
    /// uploads, and nothing writes to a default location behind their back.
    func saveHTML() {
        guard !html.isEmpty else { return }
        guard let url = savePanelURL(suggestedName: "\(defaultFileName).html", type: "html") else { return }

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            savedURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePDF() async {
        guard !html.isEmpty else { return }
        guard let url = savePanelURL(suggestedName: "\(defaultFileName).pdf", type: "pdf") else { return }

        do {
            try await PDFExporter().writePDF(fromHTML: html, to: url)
            savedURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealSaved() {
        guard let savedURL else { return }
        NSWorkspace.shared.selectFile(savedURL.path, inFileViewerRootedAtPath: "")
    }

    func openSaved() {
        guard let savedURL else { return }
        NSWorkspace.shared.open(savedURL)
    }

    private var defaultFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let machine = redactIdentifiers ? "Mac" : (Host.current().localizedName ?? "Mac")
        let safeMachine = machine.replacingOccurrences(of: "/", with: "-")
        return "DiagClean-\(safeMachine)-\(formatter.string(from: Date()))"
    }

    private func savePanelURL(suggestedName: String, type: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = type == "pdf" ? [.pdf] : [.html]
        panel.canCreateDirectories = true
        panel.message = "Choose where to save the diagnostic report."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
