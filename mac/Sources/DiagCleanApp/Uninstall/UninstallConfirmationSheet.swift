import SwiftUI
import DiagCleanKit

/// The last screen before anything moves.
///
/// Like Clean's, it lists every path rather than a sample. Unlike Clean's, its headline
/// is that this is recoverable: everything goes to the Trash, and Finder's Put Back
/// restores it. That difference is the point — it is why removing the wrong app is a
/// recoverable mistake here and deleting the wrong cache is not.
struct UninstallConfirmationSheet: View {
    let app: InstalledApp
    let includeApp: Bool
    let leftovers: [LeftoverItem]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var totalBytes: Int64 {
        leftovers.reduce(includeApp ? app.sizeBytes : 0) { $0 + $1.sizeBytes }
    }
    private var itemCount: Int { leftovers.count + (includeApp ? 1 : 0) }
    private var likelyCount: Int { leftovers.filter { $0.confidence == .likely }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 580, height: 480)
        .background(Theme.windowBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(includeApp ? "Remove \(app.name)?" : "Remove \(app.name)'s leftover files?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            HStack(alignment: .top, spacing: Theme.Space.s) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.callout)
                Text("\(itemCount) item\(itemCount == 1 ? "" : "s"), \(ByteFormat.string(totalBytes)), moved to the Trash. Nothing is deleted — Put Back restores it all.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if likelyCount > 0 {
                // Anything included on a name match rather than a bundle-ID match is
                // called out here specifically, because that is where a wrong removal
                // would come from.
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(Theme.destructive)
                        .font(.callout)
                    Text("\(likelyCount) of these matched by name, not by bundle ID. Worth a second look below.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if includeApp {
                    row(
                        title: "Application",
                        path: app.path,
                        size: app.sizeBytes,
                        isLikely: false
                    )
                    Divider().padding(.leading, Theme.Space.l)
                }

                ForEach(leftovers) { item in
                    row(
                        title: item.location,
                        path: item.path,
                        size: item.sizeBytes,
                        isLikely: item.confidence == .likely
                    )
                    Divider().padding(.leading, Theme.Space.l)
                }
            }
            .padding(.vertical, Theme.Space.s)
        }
    }

    private func row(title: String, path: String, size: Int64, isLikely: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Space.xs) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                    if isLikely {
                        Text("name match")
                            .font(.caption2)
                            .foregroundStyle(Theme.destructive)
                    }
                }
                Text(PathDisplay.abbreviate(path))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Space.m)
            Text(ByteFormat.string(size))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .sizeStyle()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
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

            Button("Move to Trash", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(Theme.Space.l)
        .background(.bar)
    }
}
