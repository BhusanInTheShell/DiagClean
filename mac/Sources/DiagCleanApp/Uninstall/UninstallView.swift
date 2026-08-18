import SwiftUI
import AppKit
import DiagCleanKit

struct UninstallView: View {
    @State private var model = UninstallViewModel()

    var body: some View {
        Group {
            switch model.phase {
            case .removing:
                UninstallRunningView(progress: model.progress, onCancel: { model.cancel() })
            case .finished:
                if let report = model.report {
                    UninstallResultView(report: report, logURL: model.logURL, onDone: { model.finish() })
                }
            case .loadingApps, .browsing:
                browser
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle("Uninstall")
        .task { model.loadIfNeeded() }
        .sheet(isPresented: $model.isConfirmationPresented) {
            if let app = model.selectedApp {
                UninstallConfirmationSheet(
                    app: app,
                    includeApp: model.includeApp,
                    leftovers: model.selectedLeftovers,
                    onCancel: { model.isConfirmationPresented = false },
                    onConfirm: { model.confirmAndRemove() }
                )
            }
        }
    }

    private var browser: some View {
        HSplitView {
            appList
                .frame(minWidth: 240, idealWidth: 290, maxWidth: 360)
            detail
                .frame(minWidth: 340, maxWidth: .infinity)
        }
    }

    // MARK: - App list

    private var appList: some View {
        VStack(spacing: 0) {
            if model.phase == .loadingApps {
                VStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Reading applications…")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                searchField
                Divider()
                List(model.filteredApps, selection: Binding(
                    get: { model.selectedApp?.id },
                    set: { id in
                        if let app = model.apps.first(where: { $0.id == id }) { model.select(app) }
                    }
                )) { app in
                    AppRow(app: app).tag(app.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
            TextField("Search applications", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                LeftoverReview(app: app, model: model)
                Divider()
                actionBar(app: app)
            }
        } else {
            CleanMessageView(
                icon: "trash",
                title: "Select an application",
                message: "DiagClean will show the app and everything it left behind before anything moves."
            )
        }
    }

    private func actionBar(app: InstalledApp) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedCount == 0
                     ? "Nothing selected"
                     : "\(ByteFormat.string(model.selectedBytes)) selected")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .sizeStyle()
                Text("\(model.selectedCount) item\(model.selectedCount == 1 ? "" : "s") · moved to the Trash")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Button("Move to Trash…") {
                model.requestConfirmation()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canRemove)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
        .background(.bar)
    }
}

// MARK: - App row

private struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .font(.callout)
                    .foregroundStyle(app.isAppleSoftware ? Theme.tertiaryText : Theme.primaryText)
                    .lineLimit(1)
                if app.isAppleSoftware {
                    Text("Part of macOS")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                } else if !app.version.isEmpty {
                    Text(app.version)
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }

            Spacer(minLength: Theme.Space.s)

            Text(ByteFormat.string(app.sizeBytes))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .sizeStyle()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Leftover review

private struct LeftoverReview: View {
    let app: InstalledApp
    let model: UninstallViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                header

                if let refusal = model.refusal {
                    RefusalBanner(refusal: refusal)
                }

                bundleRow

                if model.isScanningLeftovers {
                    HStack(spacing: Theme.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("Looking for files left behind…")
                            .font(.callout)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(Theme.Space.m)
                } else if model.leftovers.isEmpty {
                    Text("No leftover files found for this app.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(Theme.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                } else {
                    leftoverSection
                }
            }
            .padding(Theme.Space.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(app.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(app.bundleIdentifier.isEmpty ? app.path : app.bundleIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.tertiaryText)
                .textSelection(.enabled)
        }
    }

    /// The bundle is its own tick, separate from the leftovers, so "clear this app's
    /// data but keep the app" is a thing somebody can actually do.
    private var bundleRow: some View {
        HStack(spacing: Theme.Space.m) {
            Toggle("", isOn: Binding(
                get: { model.includeApp },
                set: { model.includeApp = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(model.refusal != nil)

            VStack(alignment: .leading, spacing: 1) {
                Text("The application itself")
                    .font(.callout)
                    .foregroundStyle(Theme.primaryText)
                Text(PathDisplay.abbreviate(app.path))
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Space.m)

            Text(ByteFormat.string(app.sizeBytes))
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .sizeStyle()
        }
        .padding(Theme.Space.m)
        .cardSurface()
    }

    private var leftoverSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Left behind")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button("Select All") { model.selectAllLeftovers() }
                    .buttonStyle(.link)
                    .font(.caption)
                Button("None") { model.deselectAllLeftovers() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            if model.likelyCount > 0 {
                // Explains why some rows arrive unticked, rather than leaving somebody
                // to wonder whether the app forgot them.
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Theme.secondaryText)
                    Text("\(model.likelyCount) item\(model.likelyCount == 1 ? " matches" : "s match") this app's name rather than its bundle ID. Left unticked — check the paths before including them.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(Theme.Space.s)
                .cardSurface()
            }

            VStack(spacing: 0) {
                ForEach(model.leftovers) { item in
                    LeftoverRow(item: item, model: model)
                    if item.id != model.leftovers.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
            .cardSurface()
        }
    }
}

private struct LeftoverRow: View {
    let item: LeftoverItem
    let model: UninstallViewModel

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Toggle("", isOn: Binding(
                get: { model.isSelected(item) },
                set: { _ in model.toggle(item) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Space.s) {
                    Text(item.location)
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                    if item.confidence == .likely {
                        Text(item.confidence.label)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.separator.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
                Text(PathDisplay.abbreviate(item.path))
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
            }

            Spacer(minLength: Theme.Space.m)

            Text(ByteFormat.string(item.sizeBytes))
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .sizeStyle()
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }
}

private struct RefusalBanner: View {
    let refusal: UninstallRefusal

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.destructive)
            Text(refusal.explanation)
                .font(.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
