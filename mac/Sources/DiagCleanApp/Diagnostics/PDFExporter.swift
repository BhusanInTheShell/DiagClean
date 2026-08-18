import Foundation
import AppKit
import WebKit

/// Produces a PDF from the report's HTML.
///
/// One renderer, two formats. The CLI maintains a separate PDF builder alongside its
/// HTML one, so every change has to be made twice and the two can quietly disagree about
/// what the report says. Rendering the same document guarantees they cannot.
///
/// **The PDF is a single continuous page rather than paginated sheets**, and that is a
/// deliberate retreat rather than an oversight. `NSPrintOperation` is the call that
/// paginates properly, and on a detached `WKWebView` it hangs the main thread outright —
/// it wrote nothing at all and left the app unresponsive. An earlier variant that
/// resized the operation's view produced a 311 MB file with three million objects and no
/// end marker. `createPDF` is fast, reliable and correct; its output is one tall page,
/// which reads fine on screen and attaches to a ticket, and which prints scaled to one
/// sheet rather than across several.
///
/// The HTML remains the primary format and is fully paginated by any browser's own
/// print, which is the route to take when properly paged output actually matters.
@MainActor
final class PDFExporter {
    enum ExportError: LocalizedError {
        case renderFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed(let reason): return "The PDF could not be produced: \(reason)"
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?
    private var delegate: LoadDelegate?

    func writePDF(fromHTML html: String, to url: URL) async throws {
        let data = try await pdfData(fromHTML: html)
        try data.write(to: url)
    }

    private func pdfData(fromHTML html: String) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        // The report contains no scripts by construction, and a diagnostic document has
        // no business running any.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        // A4 width at 96dpi, so the layout matches what the HTML looks like on paper
        // rather than being rendered at some arbitrary window width.
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration
        )
        self.webView = webView

        let delegate = LoadDelegate { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.renderPDF()
            case .failure(let error):
                self.finish(.failure(error))
            }
        }
        self.delegate = delegate
        webView.navigationDelegate = delegate

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func renderPDF() {
        guard let webView else { return }
        webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            self?.finish(result.mapError { $0 as Error })
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        self.webView = nil
        self.delegate = nil
        continuation?.resume(with: result)
    }

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        private let completion: (Result<Void, Error>) -> Void

        init(completion: @escaping (Result<Void, Error>) -> Void) {
            self.completion = completion
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            completion(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            completion(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            completion(.failure(error))
        }
    }
}
