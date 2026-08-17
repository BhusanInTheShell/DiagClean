import SwiftUI
import DiagCleanKit

/// The last screen before anything is removed.
///
/// It shows every single path, not a summary and not a sample. The whole safety model
/// rests on somebody being able to see what they agreed to, and a list that says
/// "and 340 others" is a list nobody agreed to. It is scrollable and it is long on
/// purpose.
///
/// The confirm button is not the default action. Return dismisses, Escape dismisses,
/// and deleting takes a deliberate click — a technician tabbing through the app at
/// speed should not be able to delete anything by reflex.
struct CleanConfirmationSheet: View {
    let items: [CleanItem]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .background(Theme.windowBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Remove \(items.count) item\(items.count == 1 ? "" : "s")?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.destructive)
                    .font(.callout)
                // Said plainly, because it is the one thing that cannot be undone.
                // Uninstall moves things to the Trash; Clean does not, because
                // relocating a cache would free no space at all.
                Text("This deletes \(ByteFormat.string(totalBytes)) permanently. These files are not moved to the Trash.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.ownerLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.secondaryText)
                            Text(PathDisplay.abbreviate(item.path))
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: Theme.Space.m)
                        Text(ByteFormat.string(item.sizeBytes))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .sizeStyle()
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().padding(.leading, Theme.Space.l)
                }
            }
            .padding(.vertical, Theme.Space.s)
        }
    }

    private var footer: some View {
        HStack {
            Text(ByteFormat.string(totalBytes))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .sizeStyle()

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Delete Permanently", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(Theme.destructive)
        }
        .padding(Theme.Space.l)
        .background(.bar)
    }
}
