import SwiftUI
import DiagCleanKit

struct UninstallRunningView: View {
    let progress: UninstallProgress?
    let onCancel: () -> Void

    private var fraction: Double {
        guard let progress, progress.totalItems > 0 else { return 0 }
        return Double(progress.itemsCompleted) / Double(progress.totalItems)
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            VStack(spacing: Theme.Space.s) {
                Text("Moving to Trash")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.primaryText)

                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 320)

                if let progress {
                    Text("\(progress.itemsCompleted) of \(progress.totalItems) · \(ByteFormat.string(progress.bytesFreed))")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .sizeStyle()
                    Text(PathDisplay.abbreviate(progress.currentPath))
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 420)
                }
            }

            Button("Stop", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }
}

struct UninstallResultView: View {
    let report: UninstallReport
    let logURL: URL?
    let onDone: () -> Void

    private var succeeded: Bool { report.failures.isEmpty && !report.wasCancelled }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: succeeded ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(succeeded ? Theme.accent : Theme.secondaryText)

                VStack(spacing: Theme.Space.xs) {
                    Text(report.wasCancelled ? "Stopped" : (report.appRemoved ? "Removed \(report.appName)" : "Finished"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                    Text("\(ByteFormat.string(report.bytesFreed)) moved to the Trash · \(report.leftoversRemoved) leftover item\(report.leftoversRemoved == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .sizeStyle()
                    // The recovery route, stated rather than implied. This is the whole
                    // reason Uninstall trashes instead of deleting.
                    Text("Still in the Trash until you empty it. Finder's Put Back restores everything to where it was.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                if !report.failures.isEmpty {
                    failureList
                }

                HStack(spacing: Theme.Space.m) {
                    Button("Open Trash") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
                        )
                    }
                    if let logURL {
                        Button("Open Log") {
                            NSWorkspace.shared.selectFile(logURL.path, inFileViewerRootedAtPath: "")
                        }
                    }
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, Theme.Space.s)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.xxl)
        }
    }

    private var failureList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("\(report.failures.count) item\(report.failures.count == 1 ? "" : "s") could not be moved")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.primaryText)

            ForEach(report.failures, id: \.path) { failure in
                VStack(alignment: .leading, spacing: 1) {
                    Text(PathDisplay.abbreviate(failure.path))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(failure.reason)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
