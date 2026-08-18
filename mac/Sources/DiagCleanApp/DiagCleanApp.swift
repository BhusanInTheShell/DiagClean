import SwiftUI
import DiagCleanKit

@main
struct DiagCleanApp: App {
    /// Off by default. A menu bar item takes a strip of screen the user did not offer,
    /// so it is something they turn on rather than something they have to turn off.
    @AppStorage("menuBarEnabled") private var menuBarEnabled = false
    @State private var menuBarModel = StatusViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Dark by default, as the brief asks: this is a tool someone has open
                // beside a ticket queue for a whole shift, and a bright panel of
                // greyscale rows is the kind of glare that wears on you by hour six.
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1040, height: 680)
        .commands {
            // Nothing here creates documents, so the New/Open items would be dead
            // weight in the menu bar.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Toggle("Show in Menu Bar", isOn: $menuBarEnabled)
            }
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            StatusMenuBarContent(
                status: menuBarModel.status,
                health: menuBarModel.overallHealth,
                isEnabled: $menuBarEnabled
            )
        } label: {
            StatusMenuBarLabel(status: menuBarModel.status, health: menuBarModel.overallHealth)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: menuBarEnabled, initial: true) { _, enabled in
            // Sampling only runs while something is actually displaying it.
            enabled ? menuBarModel.start() : menuBarModel.stop()
        }
    }
}
