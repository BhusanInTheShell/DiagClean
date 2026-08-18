import SwiftUI
import AppKit
import DiagCleanKit

struct AnalyzeView: View {
    @State private var model = AnalyzeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            content
            Divider()
            statusBar
        }
        .background(Theme.windowBackground)
        .navigationTitle("Analyze")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
                .help("Measure this folder again")
            }
        }
        .task { model.loadIfNeeded() }
        .sheet(item: $model.pendingRemoval) { pending in
            AnalyzeConfirmationSheet(
                entry: pending.entry,
                sensitivity: pending.sensitivity,
                onCancel: { model.cancelRemoval() },
                onConfirm: { model.confirmRemoval() }
            )
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: Theme.Space.xs) {
            Button {
                model.goToParent()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(model.parentPath == nil)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Go to enclosing folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Button(crumb.name) {
                            model.navigate(to: crumb.path)
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(
                            index == model.breadcrumb.count - 1 ? Theme.primaryText : Theme.secondaryText
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .defaultScrollAnchor(.trailing)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty && model.isScanning {
            VStack(spacing: Theme.Space.s) {
                ProgressView().controlSize(.small)
                Text("Measuring…")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                Button("Cancel") { model.cancelScan() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, Theme.Space.s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            CleanMessageView(
                icon: "folder",
                title: "Nothing here",
                message: model.unreadableCount > 0
                    ? "This folder could not be read. It may need permissions DiagClean does not have."
                    : "This folder is empty."
            )
        } else {
            entryList
        }
    }

    private var entryList: some View {
        List(model.entries, selection: $model.selectedEntryID) { entry in
            EntryRow(entry: entry, largest: model.largestEntryBytes, total: model.totalBytes)
                .tag(entry.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.open(entry) }
                .contextMenu {
                    if entry.isDirectory {
                        Button("Open") { model.open(entry) }
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "")
                    }
                    Divider()
                    Button("Move to Trash…") { model.requestRemoval(of: entry) }
                }
        }
        .listStyle(.inset)
        // Double-click opens, but a disk browser should be walkable without a mouse:
        // Return descends into the selected folder, Command-Up climbs back out.
        .onKeyPress(.return) {
            guard let entry = model.selectedEntry, entry.isDirectory else { return .ignored }
            model.open(entry)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard let entry = model.selectedEntry, entry.isDirectory else { return .ignored }
            model.open(entry)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard model.parentPath != nil else { return .ignored }
            model.goToParent()
            return .handled
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                if let removal = model.lastRemoval, removal.succeeded {
                    Text("Moved \(removal.name) to the Trash · \(ByteFormat.string(removal.bytesFreed))")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                } else if let message = model.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Theme.destructive)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(ByteFormat.string(model.totalBytes)) in \(model.entries.count) item\(model.entries.count == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                        .sizeStyle()
                    if model.isScanning {
                        Text("still measuring…")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            Spacer()

            if model.errorMessage != nil || model.lastRemoval != nil {
                Button("Dismiss") { model.dismissMessage() }
            }

            Button("Reveal in Finder") {
                guard let entry = model.selectedEntry else { return }
                NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "")
            }
            .disabled(model.selectedEntry == nil)

            // One item at a time by design: Analyze can reach anywhere, so there is no
            // multi-selection here to get wrong.
            Button("Move to Trash…") {
                guard let entry = model.selectedEntry else { return }
                model.requestRemoval(of: entry)
            }
            .disabled(model.selectedEntry == nil)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(.bar)
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry: DiskEntry
    let largest: Int64
    let total: Int64

    private var fraction: Double {
        guard largest > 0 else { return 0 }
        return Double(entry.sizeBytes) / Double(largest)
    }

    private var percentOfTotal: Double {
        guard total > 0 else { return 0 }
        return Double(entry.sizeBytes) / Double(total) * 100
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? Theme.accent : Theme.tertiaryText)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.callout)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Scaled against the largest sibling rather than the total, so the bars
                // stay readable when one folder dominates — which in a disk browser is
                // most of the time.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.separator.opacity(0.4))
                            .frame(height: 3)
                        Capsule()
                            .fill(entry.isDirectory ? Theme.accent.opacity(0.7) : Theme.tertiaryText.opacity(0.5))
                            .frame(width: max(2, geometry.size.width * fraction), height: 3)
                    }
                }
                .frame(height: 3)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormat.string(entry.sizeBytes))
                    .font(.callout)
                    .foregroundStyle(Theme.primaryText)
                    .sizeStyle()
                Text(String(format: "%.0f%%", percentOfTotal))
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                    .sizeStyle()
            }
            .frame(width: 84, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(entry.isDirectory ? Theme.tertiaryText : .clear)
        }
        .padding(.vertical, 4)
    }
}
