import SwiftUI
import DiagCleanKit

struct OptimizeView: View {
    @State private var model = OptimizeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            content
            if model.phase == .choosing {
                Divider()
                actionBar
            }
        }
        .background(Theme.windowBackground)
        .navigationTitle("Optimize")
        .sheet(isPresented: $model.isConfirmationPresented) {
            OptimizeConfirmationSheet(
                actions: model.selectedActions,
                disruptive: model.disruptiveSelection,
                onCancel: { model.isConfirmationPresented = false },
                onConfirm: { model.confirmAndRun() }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .choosing:
            chooser
        case .running:
            running
        case .finished:
            if let report = model.report {
                OptimizeResultView(report: report, onDone: { model.startOver() })
            }
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Maintenance")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("A short list of well-understood fixes. Each one says what it changes and what you'll notice.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.bottom, Theme.Space.xs)

                ForEach(model.available) { action in
                    ActionRow(
                        action: action,
                        isOn: model.isSelected(action),
                        toggle: { model.toggle(action) }
                    )
                }

                if !model.unavailable.isEmpty {
                    unavailableSection
                }
            }
            .padding(Theme.Space.xl)
        }
    }

    /// Shown rather than hidden. A technician looking for "flush DNS" and not finding it
    /// will assume the tool cannot do it; saying it needs admin, and where to get it,
    /// answers the question instead.
    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Needs administrator access")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("DiagClean does not ask for your password. Run these from the DiagClean CLI with sudo.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            ForEach(model.unavailable) { action in
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.callout)
                        .foregroundStyle(Theme.tertiaryText)
                    Text(action.fixes)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Running

    private var running: some View {
        VStack(spacing: Theme.Space.l) {
            VStack(spacing: Theme.Space.s) {
                Text("Running maintenance")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.primaryText)

                if let progress = model.progress {
                    ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(width: 320)
                    Text(progress.action.title)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Button("Stop", action: { model.cancel() })
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: Theme.Space.m) {
            Text(model.selectedCount == 0
                 ? "Nothing selected"
                 : "\(model.selectedCount) action\(model.selectedCount == 1 ? "" : "s") selected")
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)

            Spacer()

            Button("Run…") { model.requestConfirmation() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRun)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
        .background(.bar)
    }
}

// MARK: - Action row

private struct ActionRow: View {
    let action: OptimizationAction
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Space.xs) {
                    Text(action.title)
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                    if action.impact.isDisruptive {
                        Text(action.impact == .prolonged ? "takes hours" : "you'll notice this")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.separator.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }

                Text(action.fixes)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                // The consequence, always visible rather than tucked into the
                // confirmation. Somebody deciding whether to tick the box is the person
                // who needs to know what it does to the machine.
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                    Text(action.sideEffect)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Result

struct OptimizeResultView: View {
    let report: OptimizeReport
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: report.failureCount == 0 ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(report.failureCount == 0 ? Theme.accent : Theme.secondaryText)

                Text(report.wasCancelled ? "Stopped" : "Finished")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.primaryText)

                VStack(spacing: 0) {
                    ForEach(report.outcomes) { outcome in
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Image(systemName: outcome.succeeded ? "checkmark" : "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(outcome.succeeded ? Theme.accent : Theme.destructive)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(outcome.action.title)
                                    .font(.callout)
                                    .foregroundStyle(Theme.primaryText)
                                // The command's own words, not a guess at what happened.
                                Text(outcome.message)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.vertical, Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if outcome.id != report.outcomes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(Theme.Space.m)
                .cardSurface()

                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.xxl)
        }
    }
}
