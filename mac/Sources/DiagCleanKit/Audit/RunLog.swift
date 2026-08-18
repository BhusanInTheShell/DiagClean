import Foundation

/// Appends a plain-text record of every run that touched the disk.
///
/// Writes to the same directory the CLI logs to, so a machine has one audit trail no
/// matter which tool did the work. The format is deliberately readable without any
/// tooling: the situation this exists for is a technician being asked, weeks later,
/// what they did to somebody's laptop, and the answer needs to survive being pasted
/// into a ticket.
public struct RunLog: Sendable {
    private let directory: String
    private let now: @Sendable () -> Date

    public init(
        directory: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.now = now
    }

    public init(user: UserPaths = .current()) {
        self.init(directory: user.logsDirectory)
    }

    public var currentLogFileURL: URL { logFileURL(prefix: "clean") }

    public var currentUninstallLogFileURL: URL { logFileURL(prefix: "uninstall") }

    private func logFileURL(prefix: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return URL(fileURLWithPath: directory)
            .appendingPathComponent("\(prefix)-\(formatter.string(from: now())).log")
    }

    @discardableResult
    public func record(plan: CleanPlan, report: CleanReport) -> URL? {
        var text = ""
        text += "---- Clean run at \(Self.timestamp(report.startedAt)) by \(NSUserName()) on \(Host.current().localizedName ?? "unknown") ----\n"
        text += "planned: \(plan.itemCount) items, \(ByteFormat.string(plan.totalBytes))\n"
        text += "removed: \(report.itemsRemoved) items, \(ByteFormat.string(report.bytesFreed)) freed"
        text += report.wasCancelled ? " (cancelled partway)\n" : "\n"

        for item in plan.items {
            let removed = report.failures.contains { $0.path == item.path } ? "FAILED " : "removed"
            text += "  \(removed) [\(item.category.rawValue)] \(ByteFormat.string(item.sizeBytes).padded(to: 10)) \(item.path)\n"
        }
        for failure in report.failures {
            text += "  reason: \(failure.path) — \(failure.reason)\n"
        }
        text += "\n"

        return append(text)
    }

    @discardableResult
    public func record(plan: UninstallPlan, report: UninstallReport) -> URL? {
        var text = ""
        text += "---- Uninstall run at \(Self.timestamp(report.startedAt)) by \(NSUserName()) on \(Host.current().localizedName ?? "unknown") ----\n"
        text += "app: \(plan.app.name) \(plan.app.version) (\(plan.app.bundleIdentifier)) at \(plan.app.path)\n"
        text += "planned: \(plan.itemCount) items, \(ByteFormat.string(plan.totalBytes))\n"
        text += "moved to Trash: \(report.appRemoved ? "bundle + " : "")\(report.leftoversRemoved) leftover(s), \(ByteFormat.string(report.bytesFreed))"
        text += report.wasCancelled ? " (cancelled partway)\n" : "\n"

        if plan.includeApp {
            let state = report.appRemoved ? "trashed" : "FAILED "
            text += "  \(state) [bundle]    \(ByteFormat.string(plan.app.sizeBytes).padded(to: 10)) \(plan.app.path)\n"
        }
        for item in plan.leftovers {
            let state = report.failures.contains { $0.path == item.path } ? "FAILED " : "trashed"
            // The confidence tier is recorded too: if a removal is ever questioned, the
            // useful question is whether it was a certain match or a judgement call.
            text += "  \(state) [\(item.confidence.rawValue)] \(ByteFormat.string(item.sizeBytes).padded(to: 10)) \(item.path)\n"
        }
        for failure in report.failures {
            text += "  reason: \(failure.path) — \(failure.reason)\n"
        }
        text += "\n"

        return append(text, to: currentUninstallLogFileURL)
    }

    private func append(_ text: String, to url: URL? = nil) -> URL? {
        guard let data = text.data(using: .utf8) else { return nil }
        let url = url ?? currentLogFileURL

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url)
            }
            return url
        } catch {
            // A failed log write must never take down a run that already succeeded, and
            // must never be the reason a technician can't finish a job.
            return nil
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
