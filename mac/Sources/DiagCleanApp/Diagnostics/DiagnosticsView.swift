import SwiftUI
import WebKit
import DiagCleanKit

struct DiagnosticsView: View {
    @State private var model = DiagnosticsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            actionBar
        }
        .background(Theme.windowBackground)
        .navigationTitle("Diagnostics")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .configuring:
            configuration
        case .generating:
            VStack(spacing: Theme.Space.s) {
                ProgressView().controlSize(.small)
                Text("Collecting…")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ReportPreview(html: model.html)
        }
    }

    // MARK: - Configuration

    private var configuration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("What goes in the report")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    // The framing this screen needs: a diagnostic report is not a
                    // dangerous action, it is a disclosure. The risk is where the file
                    // ends up, so the screen leads with what is in it.
                    Text("Reports are saved where you choose and sent nowhere. Anything you leave out is never collected.")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.bottom, Theme.Space.xs)

                ForEach(ReportSection.allCases) { section in
                    SectionRow(
                        section: section,
                        isOn: model.selectedSections.contains(section),
                        toggle: { model.toggle(section) }
                    )
                }

                privacyCard
            }
            .padding(Theme.Space.xl)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Toggle(isOn: Binding(
                get: { model.redactIdentifiers },
                set: { model.redactIdentifiers = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redact identifying details")
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                    Text("Replaces the computer name, the user's name, and IP and MAC addresses with “\(ReportRedaction.marker)”. macOS version and hardware are kept.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            if !model.redactIdentifiers && !model.sectionsCarryingIdentifiers.isEmpty {
                // Names the sections rather than warning in general terms, so the
                // technician knows exactly what a forwarded copy would reveal.
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.secondaryText)
                    Text("\(model.sectionsCarryingIdentifiers.map(\.title).joined(separator: " and ")) will identify this machine and its user.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                if let message = model.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Theme.destructive)
                        .lineLimit(2)
                } else if let saved = model.savedURL {
                    Text("Saved to \(PathDisplay.abbreviate(saved.path))")
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if model.phase == .ready {
                    Text("Report ready")
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                } else {
                    Text("\(model.selectedSections.count) of \(ReportSection.allCases.count) sections selected")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer()

            switch model.phase {
            case .configuring, .generating:
                Button("Generate Report") { model.generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canGenerate)
            case .ready:
                if model.savedURL != nil {
                    Button("Open") { model.openSaved() }
                    Button("Show in Finder") { model.revealSaved() }
                }
                Button("Back") { model.startOver() }
                Button("Save HTML…") { model.saveHTML() }
                Button("Save PDF…") {
                    Task { await model.savePDF() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
        .background(.bar)
    }
}

// MARK: - Section row

private struct SectionRow: View {
    let section: ReportSection
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text(section.title)
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                    if section.carriesIdentifiers {
                        Text("identifying")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.separator.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
                // Says what leaves the machine, in the words of the person deciding
                // whether to attach it.
                Text(section.contents)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Preview

/// Shows the actual report before it is saved, rendered by the same engine that will
/// produce the PDF. What the technician reviews here is precisely what they will attach.
private struct ReportPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
