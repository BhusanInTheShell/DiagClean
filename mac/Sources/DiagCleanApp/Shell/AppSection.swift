import SwiftUI

/// The app's six areas, in the order a technician actually works: find out what's
/// wrong, reclaim space, remove software, investigate the disk, tidy up, then produce
/// something to attach to the ticket.
///
/// All six are built.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case status
    case clean
    case uninstall
    case analyze
    case optimize
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .clean: return "Clean"
        case .uninstall: return "Uninstall"
        case .analyze: return "Analyze"
        case .optimize: return "Optimize"
        case .diagnostics: return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .status: return "waveform.path.ecg"
        case .clean: return "sparkles"
        case .uninstall: return "trash"
        case .analyze: return "chart.pie"
        case .optimize: return "wrench.and.screwdriver"
        case .diagnostics: return "doc.text.magnifyingglass"
        }
    }
}
