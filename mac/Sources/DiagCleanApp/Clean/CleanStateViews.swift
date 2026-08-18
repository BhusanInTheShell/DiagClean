import SwiftUI
import DiagCleanKit

/// A quiet full-screen message. Used for every state that isn't a list: ready, empty,
/// error. One icon, one line, one sentence.
struct CleanMessageView: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.secondaryText

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(tint)
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }
}

struct CleanScanningView: View {
    let status: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ProgressView()
                .controlSize(.small)
            VStack(spacing: Theme.Space.xs) {
                Text("Scanning")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                // The live path is the reassurance that this is reading, not deleting.
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
            }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }
}

struct CleanRunningView: View {
    let progress: CleanProgress?
    let onCancel: () -> Void

    private var fraction: Double {
        guard let progress, progress.totalItems > 0 else { return 0 }
        return Double(progress.itemsCompleted) / Double(progress.totalItems)
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            VStack(spacing: Theme.Space.s) {
                Text("Cleaning")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.primaryText)

                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 320)

                if let progress {
                    Text("\(progress.itemsCompleted) of \(progress.totalItems) · \(ByteFormat.string(progress.bytesFreed)) freed")
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

            // Cancel stops between items, never mid-item, so stopping here always
            // leaves the machine in a state the result screen can describe exactly.
            Button("Stop", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xxl)
    }
}

struct CleanResultView: View {
    let report: CleanReport
    let logURL: URL?
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Image(systemName: report.wasCancelled ? "stop.circle" : "checkmark.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(report.wasCancelled ? Theme.secondaryText : Theme.accent)

                VStack(spacing: Theme.Space.xs) {
                    Text(report.wasCancelled ? "Stopped" : "Done")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                    // A cancelled run is a partial run, and says so. Reporting it as a
                    // no-op would be the most misleading thing this screen could do.
                    Text("\(ByteFormat.string(report.bytesFreed)) freed from \(report.itemsRemoved) item\(report.itemsRemoved == 1 ? "" : "s")")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .sizeStyle()
                }

                if !report.failures.isEmpty {
                    failureList
                }

                HStack(spacing: Theme.Space.m) {
                    if let logURL {
                        Button("Open Log") {
                            NSWorkspace.shared.selectFile(logURL.path, inFileViewerRootedAtPath: "")
                        }
                    }
                    Button("Scan Again", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, Theme.Space.s)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.xxl)
        }
    }

    /// Every failure, with its reason. A tool that quietly succeeds at 9 things and
    /// hides the 10th is one a technician has to double-check by hand every time.
    private var failureList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("\(report.failures.count) item\(report.failures.count == 1 ? "" : "s") could not be removed")
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
