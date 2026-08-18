import Foundation

public struct UninstallProgress: Sendable {
    public let itemsCompleted: Int
    public let totalItems: Int
    public let bytesFreed: Int64
    public let currentPath: String
}

/// Why an uninstall was refused before it began. Checked at plan time so the UI can
/// explain, and again at execution time so a change in the meantime cannot slip past.
public enum UninstallRefusal: Equatable, Sendable {
    case appIsRunning(name: String)
    case appleSoftware(name: String)
    case selfRemoval

    public var explanation: String {
        switch self {
        case .appIsRunning(let name):
            return "\(name) is running. Quit it first — removing a running app can lose unsaved work."
        case .appleSoftware(let name):
            return "\(name) is part of macOS. DiagClean does not remove Apple software."
        case .selfRemoval:
            return "DiagClean cannot uninstall itself."
        }
    }
}

/// The only code in DiagClean that removes an application.
///
/// Where `CleanExecutor` deletes permanently, this moves everything to the Trash.
/// The asymmetry is deliberate and inherited from the CLI: a cache that turns out to
/// have been wanted costs seconds to rebuild, whereas removing the wrong application
/// costs a reinstall, a licence key, and whatever local data went with it. Caches are
/// permanent because trashing them would free no space at all; apps are recoverable
/// because the mistake is expensive.
///
/// `FileManager.trashItem` is used rather than a hand-rolled move into `~/.Trash` — it
/// records the item's original location, so Finder's Put Back actually works. The CLI
/// moves files manually and loses that, which makes its "recoverable" a good deal more
/// theoretical than it sounds.
public struct UninstallExecutor: Sendable {
    private let pathGuard: PathGuard
    private let detector: RunningAppDetecting
    private let now: @Sendable () -> Date
    private let ownBundleIdentifier: String

    public init(
        pathGuard: PathGuard,
        detector: RunningAppDetecting = LiveRunningAppDetector(),
        ownBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.diagclean.mac",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pathGuard = pathGuard
        self.detector = detector
        self.ownBundleIdentifier = ownBundleIdentifier
        self.now = now
    }

    /// Everything standing between this app and removal, or `nil` if it may proceed.
    public func refusal(for app: InstalledApp) -> UninstallRefusal? {
        if app.isAppleSoftware {
            return .appleSoftware(name: app.name)
        }
        if !app.bundleIdentifier.isEmpty, app.bundleIdentifier == ownBundleIdentifier {
            return .selfRemoval
        }
        if detector.isRunning(bundleIdentifier: app.bundleIdentifier, bundlePath: app.path) {
            return .appIsRunning(name: app.name)
        }
        return nil
    }

    public func execute(
        plan: UninstallPlan,
        progress: @Sendable (UninstallProgress) -> Void = { _ in }
    ) async -> UninstallReport {
        let startedAt = now()

        // Re-checked here, not just when the plan was built. The technician may have
        // relaunched the app while reading the confirmation list.
        if let refusal = refusal(for: plan.app) {
            return UninstallReport(
                appName: plan.app.name,
                appRemoved: false,
                leftoversRemoved: 0,
                bytesFreed: 0,
                failures: [CleanFailure(path: plan.app.path, reason: refusal.explanation)],
                wasCancelled: false,
                startedAt: startedAt,
                finishedAt: now()
            )
        }

        var bytesFreed: Int64 = 0
        var leftoversRemoved = 0
        var appRemoved = false
        var failures: [CleanFailure] = []
        var wasCancelled = false
        var completed = 0

        // The bundle goes first. If the run is interrupted after this point the machine
        // is left with orphaned support files, which are harmless; interrupting the
        // other way round would leave a working app stripped of its own preferences.
        if plan.includeApp {
            if let failure = trash(plan.app.path) {
                failures.append(failure)
            } else {
                appRemoved = true
                bytesFreed += plan.app.sizeBytes
            }
            completed += 1
            progress(UninstallProgress(
                itemsCompleted: completed,
                totalItems: plan.itemCount,
                bytesFreed: bytesFreed,
                currentPath: plan.app.path
            ))
        }

        for item in plan.leftovers {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            if let failure = trash(item.path) {
                failures.append(failure)
            } else {
                leftoversRemoved += 1
                bytesFreed += item.sizeBytes
            }

            completed += 1
            progress(UninstallProgress(
                itemsCompleted: completed,
                totalItems: plan.itemCount,
                bytesFreed: bytesFreed,
                currentPath: item.path
            ))
        }

        return UninstallReport(
            appName: plan.app.name,
            appRemoved: appRemoved,
            leftoversRemoved: leftoversRemoved,
            bytesFreed: bytesFreed,
            failures: failures,
            wasCancelled: wasCancelled,
            startedAt: startedAt,
            finishedAt: now()
        )
    }

    /// Returns the failure, or `nil` when the path is gone by the time this finishes —
    /// which is the outcome that was asked for either way.
    private func trash(_ path: String) -> CleanFailure? {
        // The guard runs again here, against the same rules that admitted the path to
        // the scan. The plan may be minutes old by the time somebody confirms it.
        switch pathGuard.decide(path) {
        case .denied(let denial):
            return CleanFailure(path: path, reason: "blocked at removal time: \(denial.explanation)")
        case .allowed(let canonicalPath):
            guard FileManager.default.fileExists(atPath: canonicalPath) else {
                // Already gone. Not an error — the end state is the one that was asked
                // for, and reporting it as a failure teaches people to ignore failures.
                return nil
            }
            do {
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: canonicalPath), resultingItemURL: nil
                )
                return nil
            } catch {
                return CleanFailure(path: path, reason: (error as NSError).localizedDescription)
            }
        }
    }
}
