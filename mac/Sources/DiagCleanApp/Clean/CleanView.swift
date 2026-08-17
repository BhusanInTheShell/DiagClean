import SwiftUI
import DiagCleanKit

struct CleanView: View {
    @State private var model = CleanViewModel()
    @State private var expandedCategories: Set<CleanCategory> = []

    var body: some View {
        VStack(spacing: 0) {
            content
            if model.phase == .reviewing && model.hasFindings {
                Divider()
                actionBar
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle("Clean")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.phase == .scanning || model.phase == .cleaning)
                .help("Scan again")
            }
        }
        .task { model.scanIfNeeded() }
        .sheet(isPresented: $model.isConfirmationPresented) {
            CleanConfirmationSheet(
                items: model.selectedItems,
                onCancel: { model.isConfirmationPresented = false },
                onConfirm: { model.confirmAndClean() }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if let message = model.errorMessage {
                CleanMessageView(
                    icon: "exclamationmark.triangle",
                    title: "Couldn’t finish the scan",
                    message: message,
                    tint: Theme.destructive
                )
            } else {
                CleanMessageView(
                    icon: "sparkles",
                    title: "Ready to scan",
                    message: "Nothing is deleted until you review the list and confirm."
                )
            }
        case .scanning:
            CleanScanningView(status: model.scanStatus, onCancel: { model.cancel() })
        case .reviewing:
            if model.hasFindings {
                reviewList
            } else {
                CleanMessageView(
                    icon: "checkmark.circle",
                    title: "Nothing to clean",
                    message: "Every location DiagClean checks is already empty."
                )
            }
        case .cleaning:
            CleanRunningView(progress: model.cleanProgress, onCancel: { model.cancel() })
        case .finished:
            if let report = model.report {
                CleanResultView(
                    report: report,
                    logURL: model.logURL,
                    onDone: { model.startOver() }
                )
            }
        }
    }

    // MARK: - Review

    private var reviewList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                header

                ForEach(model.categories.filter { $0.itemCount > 0 }) { category in
                    CleanCategoryCard(
                        category: category,
                        groups: model.groups(in: category),
                        model: model,
                        isExpanded: expandedCategories.contains(category.category),
                        onToggleExpanded: {
                            if expandedCategories.contains(category.category) {
                                expandedCategories.remove(category.category)
                            } else {
                                expandedCategories.insert(category.category)
                            }
                        }
                    )
                }

                if model.skippedCount > 0 {
                    skippedNote
                }
            }
            .padding(Theme.Space.xl)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Found \(ByteFormat.string(model.scan?.totalBytes ?? 0)) that can be reclaimed")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Review what will be removed. Nothing is deleted until you confirm.")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.bottom, Theme.Space.s)
    }

    /// Skipped paths are surfaced rather than swallowed. "Why isn't my big cache in the
    /// list" should always have an answer on screen.
    private var skippedNote: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Theme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.skippedCount) location\(model.skippedCount == 1 ? "" : "s") skipped")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                Text("Protected or outside the areas DiagClean is allowed to touch.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
        }
        .padding(Theme.Space.m)
        .cardSurface()
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedCount == 0
                     ? "Nothing selected"
                     : "\(ByteFormat.string(model.selectedBytes)) selected")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .sizeStyle()
                Text("\(model.selectedCount) item\(model.selectedCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Button("Clean…") {
                model.requestConfirmation()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.selectedCount == 0)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
        .background(.bar)
    }
}

// MARK: - Category card

private struct CleanCategoryCard: View {
    let category: CategoryScan
    let groups: [CleanRowGroup]
    let model: CleanViewModel
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            categoryHeader

            if isExpanded {
                Divider().padding(.leading, Theme.Space.xl)
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        CleanGroupRow(group: group, model: model)
                        if group.id != groups.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .cardSurface()
    }

    /// The checkbox and the disclosure are two real buttons side by side rather than one
    /// row with a tap gesture. A gesture has no keyboard equivalent and no accessibility
    /// role, and a screen that can delete files should be operable without a mouse.
    /// They sit next to each other rather than nested, since a button inside a button
    /// swallows the inner one's activation.
    private var categoryHeader: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            TriStateCheckbox(
                isOn: model.isSelected(category),
                isMixed: model.isPartiallySelected(category),
                action: { model.toggle(category) }
            )
            .accessibilityLabel("Select \(category.category.title)")

            Button(action: onToggleExpanded) {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.category.title)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(category.category.summary)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: Theme.Space.m)

                    // The category's own total, not the selected subset. A number that
                    // changed to "Zero bytes" as you unticked the box made the row read
                    // like the scan had found nothing; what's *selected* belongs in the
                    // action bar, and the checkbox already says whether this is in.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormat.string(category.totalBytes))
                            .font(.headline)
                            .foregroundStyle(model.isSelected(category) || model.isPartiallySelected(category)
                                             ? Theme.primaryText : Theme.tertiaryText)
                            .sizeStyle()
                        Text("\(category.itemCount) item\(category.itemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(category.category.title), \(ByteFormat.string(category.totalBytes))")
            .accessibilityHint(isExpanded ? "Hide details" : "Show details")
        }
        .padding(Theme.Space.m)
    }
}

// MARK: - Group row

private struct CleanGroupRow: View {
    let group: CleanRowGroup
    let model: CleanViewModel

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            TriStateCheckbox(
                isOn: model.isSelected(group),
                isMixed: model.isPartiallySelected(group),
                action: { model.toggle(group) }
            )
            .accessibilityLabel("Select \(group.label)")

            Button {
                model.toggle(group)
            } label: {
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.label)
                            .font(.callout)
                            .foregroundStyle(Theme.primaryText)
                        // The real path, always. A review screen that hides where the
                        // files are is asking to be trusted rather than earning it.
                        Text(pathDescription)
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(group.items.map(\.path).joined(separator: "\n"))
                    }

                    Spacer(minLength: Theme.Space.m)

                    Text(ByteFormat.string(group.totalBytes))
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .sizeStyle()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.label), \(ByteFormat.string(group.totalBytes))")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .padding(.leading, Theme.Space.xl)
    }

    private var pathDescription: String {
        let base = PathDisplay.abbreviate(group.primaryPath)
        guard group.additionalLocationCount > 0 else { return base }
        return "\(base)  +\(group.additionalLocationCount) more"
    }
}

// MARK: - Checkbox

/// A checkbox with a mixed state, so a partly-selected category is visibly different
/// from an unselected one instead of quietly reading as "off".
private struct TriStateCheckbox: View {
    let isOn: Bool
    let isMixed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn || isMixed ? Theme.accent : Color.clear)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isOn || isMixed ? Theme.accent : Theme.separator, lineWidth: 1)
                if isMixed {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.85))
                        .frame(width: 8, height: 2)
                } else if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }
}
