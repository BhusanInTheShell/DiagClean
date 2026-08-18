import SwiftUI

@main
struct DiagCleanApp: App {
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
        }
    }
}
