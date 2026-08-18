import SwiftUI

/// The app's six areas, in the order a technician actually works: find out what's
/// wrong, reclaim space, remove software, investigate the disk, tidy up, then produce
/// something to attach to the ticket.
///
/// Only Clean is implemented. The rest are listed rather than hidden because the
/// shape of the tool is part of what a technician is deciding about when they first
/// open it — a sidebar that grows new items over time is more disorienting than one
/// that says plainly what is coming.
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

    var isImplemented: Bool {
        self != .optimize
    }

    /// Shown on the placeholder screen. Says what the section will do, so the sidebar
    /// reads as a roadmap rather than a set of dead ends.
    var plannedDescription: String {
        switch self {
        case .status:
            return "A live view of disk, memory, CPU and battery health, with an optional menu bar readout."
        case .clean:
            return ""
        case .uninstall:
            return "Pick an app, review its leftover files, and move the whole set to the Trash."
        case .analyze:
            return "Walk the disk by size to find what is actually taking up the space."
        case .optimize:
            return "A short list of conservative maintenance actions, each reporting its real result."
        case .diagnostics:
            return "Generate the full HTML or PDF diagnostic report and open it."
        }
    }
}
