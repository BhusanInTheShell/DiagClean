import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Answers whether an app is running right now.
///
/// Moving a running application to the Trash is one of the more unpleasant things a
/// cleanup tool can do: the app keeps running against files that are no longer where it
/// left them, and what happens next ranges from a crash to silent data loss on the next
/// save. The CLI does not check. This does, both before offering the removal and again
/// immediately before performing it.
///
/// Behind a protocol so the refusal path is testable without actually launching
/// something.
public protocol RunningAppDetecting: Sendable {
    func isRunning(bundleIdentifier: String, bundlePath: String) -> Bool
}

public struct LiveRunningAppDetector: RunningAppDetecting {
    public init() {}

    public func isRunning(bundleIdentifier: String, bundlePath: String) -> Bool {
        #if canImport(AppKit)
        let running = NSWorkspace.shared.runningApplications
        if !bundleIdentifier.isEmpty,
           running.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return true
        }
        // Fall back to the bundle path, which covers apps with no identifier and apps
        // running from a copy at the same location.
        let target = PathGuard.standardize(bundlePath)
        return running.contains { app in
            guard let url = app.bundleURL else { return false }
            return PathGuard.standardize(url.path) == target
        }
        #else
        return false
        #endif
    }
}
