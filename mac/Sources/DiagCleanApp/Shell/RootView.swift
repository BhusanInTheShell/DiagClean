import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .clean

    var body: some View {
        NavigationSplitView {
            // Plain rows bound to the split view's own selection. A `NavigationLink`
            // here would introduce a second, competing notion of what is selected, and
            // the two disagree on launch.
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .foregroundStyle(section.isImplemented ? Theme.primaryText : Theme.tertiaryText)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection {
            case .clean:
                CleanView()
            case .uninstall:
                UninstallView()
            case .analyze:
                AnalyzeView()
            case .status:
                StatusView()
            case .diagnostics:
                DiagnosticsView()
            default:
                ComingSoonView(section: selection)
            }
        }
        .frame(minWidth: 1020, minHeight: 600)
    }
}

/// Says what the section will do rather than apologising for not existing. A sidebar
/// entry that leads to a blank pane reads like a bug; one that explains itself reads
/// like a roadmap.
struct ComingSoonView: View {
    let section: AppSection

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: section.systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(section.title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.primaryText)
            Text(section.plannedDescription)
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text("Not built yet — available in the DiagClean CLI today.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, Theme.Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.windowBackground)
        .navigationTitle(section.title)
    }
}
