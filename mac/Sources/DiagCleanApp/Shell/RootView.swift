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
            case .optimize:
                OptimizeView()
            }
        }
        .frame(minWidth: 1020, minHeight: 600)
    }
}
