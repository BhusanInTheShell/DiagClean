import SwiftUI
import DiagCleanKit

/// Confirmation for a single removal from the disk browser.
///
/// Analyze can reach anywhere, and unlike Clean or Uninstall the app has no idea what
/// the thing being removed actually is. So the sheet leads with the full path rather
/// than a friendly label, and when the guard has flagged the item as personal data it
/// says so in as many words instead of asking the same neutral question about a cache
/// folder and somebody's photo library.
struct AnalyzeConfirmationSheet: View {
    let entry: DiskEntry
    let sensitivity: RemovalSensitivity
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var personalContainer: String? {
        if case .personal(let container) = sensitivity { return container }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Move \(entry.name) to the Trash?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)

                HStack(spacing: Theme.Space.s) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                        .foregroundStyle(Theme.secondaryText)
                    Text("\(ByteFormat.string(entry.sizeBytes))\(entry.isDirectory ? ", including everything inside it" : "")")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            // The exact path, selectable. This is the one screen where the app cannot
            // describe what the item is, so it shows precisely where it is instead.
            Text(entry.path)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

            if let personalContainer {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.destructive)
                    Text("This is in your \(personalContainer). It is personal data, not something the system regenerates.")
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }

            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Moved to the Trash, not deleted. Put Back restores it to where it is now.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(personalContainer == nil ? Theme.accent : Theme.destructive)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
        .background(Theme.windowBackground)
    }
}
