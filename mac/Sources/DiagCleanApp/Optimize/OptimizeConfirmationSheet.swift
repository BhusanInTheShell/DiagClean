import SwiftUI
import DiagCleanKit

/// The last screen before anything changes.
///
/// Unlike Clean and Uninstall, nothing here deletes a file — so the thing worth
/// confirming is not "are you sure" but "do you know what this will do to the machine
/// you are sitting at". Actions with visible consequences are called out separately, and
/// the exact commands are shown: a technician about to restart somebody's Finder is
/// entitled to see `killall Finder` before it happens rather than take it on trust.
struct OptimizeConfirmationSheet: View {
    let actions: [OptimizationAction]
    let disruptive: [OptimizationAction]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 560, height: 440)
        .background(Theme.windowBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Run \(actions.count) maintenance action\(actions.count == 1 ? "" : "s")?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)

            if disruptive.isEmpty {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Nothing is deleted. These change system state and take effect immediately.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Named individually rather than warned about in general terms, because
                // the whole risk here is a disruptive action going through as one quiet
                // tick among several harmless ones.
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.destructive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You will notice \(disruptive.count == 1 ? "this one" : "these"):")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                        ForEach(disruptive) { action in
                            Text("\(action.title) — \(action.sideEffect)")
                                .font(.callout)
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(actions) { action in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                        // Exactly what will run, verbatim.
                        ForEach(action.commands, id: \.displayString) { command in
                            Text(command.displayString)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.tertiaryText)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Run", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(disruptive.isEmpty ? Theme.accent : Theme.destructive)
        }
        .padding(Theme.Space.l)
        .background(.bar)
    }
}
