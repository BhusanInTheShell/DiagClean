import Foundation
import Testing
@testable import DiagCleanKit

private struct StubDetector: RunningAppDetecting {
    let running: Bool
    func isRunning(bundleIdentifier: String, bundlePath: String) -> Bool { running }
}

private func app(
    path: String,
    name: String = "Example",
    id: String = "com.example.app",
    size: Int64 = 1024,
    apple: Bool = false
) -> InstalledApp {
    InstalledApp(
        path: path, name: name, bundleIdentifier: id, version: "1.0",
        sizeBytes: size, lastUsed: nil, isAppleSoftware: apple
    )
}

private func leftover(_ path: String, size: Int64 = 512) -> LeftoverItem {
    LeftoverItem(path: path, sizeBytes: size, isDirectory: false, confidence: .confident, location: "Caches")
}

@Suite("UninstallExecutor")
struct UninstallExecutorTests {

    private func executor(
        allowing roots: [String],
        protected: [String] = [],
        running: Bool = false,
        ownID: String = "com.diagclean.mac"
    ) -> UninstallExecutor {
        UninstallExecutor(
            pathGuard: PathGuard(allowedRoots: roots, protectedPaths: protected),
            detector: StubDetector(running: running),
            ownBundleIdentifier: ownID
        )
    }

    // MARK: - Refusals

    /// Moving a running app to the Trash leaves it executing against files that have
    /// moved out from under it. The CLI does not check for this at all.
    @Test("refuses to remove an app that is currently running")
    func refusesRunningApp() async throws {
        let workspace = try TempWorkspace()
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")

        let sut = executor(allowing: [apps], running: true)
        let target = app(path: bundle)

        #expect(sut.refusal(for: target) == .appIsRunning(name: "Example"))

        let report = await sut.execute(plan: UninstallPlan(app: target, includeApp: true, leftovers: []))

        #expect(!report.appRemoved)
        #expect(workspace.exists(bundle), "a running app must survive the attempt")
    }

    /// Safari, Keynote, Numbers, Pages and Xcode all live in /Applications on a normal
    /// machine, and the CLI offers every one of them for removal.
    @Test("refuses to remove Apple software")
    func refusesAppleSoftware() async throws {
        let workspace = try TempWorkspace()
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Safari.app")

        let sut = executor(allowing: [apps])
        let target = app(path: bundle, name: "Safari", id: "com.apple.Safari", apple: true)

        #expect(sut.refusal(for: target) == .appleSoftware(name: "Safari"))

        let report = await sut.execute(plan: UninstallPlan(app: target, includeApp: true, leftovers: []))

        #expect(!report.appRemoved)
        #expect(workspace.exists(bundle))
    }

    @Test("refuses to uninstall itself")
    func refusesSelfRemoval() async throws {
        let workspace = try TempWorkspace()
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "DiagClean.app")

        let sut = executor(allowing: [apps], ownID: "com.diagclean.mac")
        let target = app(path: bundle, name: "DiagClean", id: "com.diagclean.mac")

        #expect(sut.refusal(for: target) == .selfRemoval)

        let report = await sut.execute(plan: UninstallPlan(app: target, includeApp: true, leftovers: []))

        #expect(!report.appRemoved)
        #expect(workspace.exists(bundle))
    }

    /// The refusal is re-evaluated inside `execute`, not only when the plan was built —
    /// somebody may relaunch the app while reading the confirmation list.
    @Test("re-checks the refusal at execution time, not just at plan time")
    func reChecksRefusalAtExecution() async throws {
        let workspace = try TempWorkspace()
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")
        let junk = try workspace.makeFile("Caches/com.example.app/blob")

        // Plan built while not running; the executor sees it running.
        let sut = executor(allowing: [apps, workspace.path("Caches")], running: true)
        let plan = UninstallPlan(
            app: app(path: bundle), includeApp: true,
            leftovers: [leftover(junk)]
        )

        let report = await sut.execute(plan: plan)

        #expect(report.failures.count == 1)
        #expect(report.leftoversRemoved == 0, "nothing at all proceeds once the app is running")
        #expect(workspace.exists(junk))
    }

    // MARK: - Removal

    @Test("re-checks the guard immediately before removing each item")
    func reChecksGuardPerItem() async throws {
        let workspace = try TempWorkspace()
        let caches = try workspace.makeDirectory("Caches")
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")
        let allowed = try workspace.makeFile("Caches/com.example.app/blob")
        let nowProtected = try workspace.makeFile("Caches/personal/photo.jpg")

        let sut = executor(
            allowing: [apps, caches],
            protected: [workspace.path("Caches", "personal")]
        )
        let plan = UninstallPlan(
            app: app(path: bundle), includeApp: false,
            leftovers: [leftover(allowed), leftover(nowProtected)]
        )

        let report = await sut.execute(plan: plan)

        #expect(report.leftoversRemoved == 1)
        #expect(workspace.exists(nowProtected), "a protected file must survive even when it is in the plan")
        #expect(report.failures[0].reason.contains("blocked at removal time"))
    }

    @Test("refuses a leftover that lies outside the allowed roots")
    func refusesOutsideRoots() async throws {
        let workspace = try TempWorkspace()
        let caches = try workspace.makeDirectory("Caches")
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")
        let stray = try workspace.makeFile("elsewhere/important.txt")

        let sut = executor(allowing: [apps, caches])
        let plan = UninstallPlan(app: app(path: bundle), includeApp: false, leftovers: [leftover(stray)])

        let report = await sut.execute(plan: plan)

        #expect(report.leftoversRemoved == 0)
        #expect(workspace.exists(stray))
    }

    @Test("removes the bundle before its leftovers")
    func removesAppFirst() async throws {
        let workspace = try TempWorkspace()
        let caches = try workspace.makeDirectory("Caches")
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")
        let junk = try workspace.makeFile("Caches/com.example.app/blob")

        let order = Mutex<[String]>([])
        let sut = executor(allowing: [apps, caches])
        let plan = UninstallPlan(
            app: app(path: bundle), includeApp: true, leftovers: [leftover(junk)]
        )

        _ = await sut.execute(plan: plan) { progress in
            order.withLock { $0.append(progress.currentPath) }
        }

        // Interrupting after the bundle leaves harmless orphans; interrupting the other
        // way round would leave a working app stripped of its own preferences.
        #expect(order.withLock { $0.first } == bundle)
    }

    @Test("counts an item that vanished before removal as done, not failed")
    func alreadyGoneIsSuccess() async throws {
        let workspace = try TempWorkspace()
        let caches = try workspace.makeDirectory("Caches")
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")
        let ghost = (caches as NSString).appendingPathComponent("com.example.gone")

        let sut = executor(allowing: [apps, caches])
        let plan = UninstallPlan(app: app(path: bundle), includeApp: false, leftovers: [leftover(ghost)])

        let report = await sut.execute(plan: plan)

        #expect(report.failures.isEmpty)
        #expect(report.leftoversRemoved == 1)
    }

    @Test("a plan can exclude the bundle and remove leftovers only")
    func leftoversOnly() async throws {
        let workspace = try TempWorkspace()
        let caches = try workspace.makeDirectory("Caches")
        let apps = try workspace.makeDirectory("Applications")
        let bundle = try workspace.makeDirectory("Applications", "Example.app")
        let junk = try workspace.makeFile("Caches/com.example.app/blob")

        let sut = executor(allowing: [apps, caches])
        let plan = UninstallPlan(app: app(path: bundle), includeApp: false, leftovers: [leftover(junk)])

        let report = await sut.execute(plan: plan)

        #expect(!report.appRemoved)
        #expect(workspace.exists(bundle), "the bundle stays when the plan excludes it")
        #expect(report.leftoversRemoved == 1)
    }

    @Test("totals count the bundle only when the plan includes it")
    func planTotals() {
        let target = app(path: "/Applications/Example.app", size: 1000)
        let items = [leftover("/a", size: 100), leftover("/b", size: 200)]

        #expect(UninstallPlan(app: target, includeApp: true, leftovers: items).totalBytes == 1300)
        #expect(UninstallPlan(app: target, includeApp: false, leftovers: items).totalBytes == 300)
        #expect(UninstallPlan(app: target, includeApp: true, leftovers: items).itemCount == 3)
    }

    @Test("orders nested leftovers deepest-first")
    func ordersDeepestFirst() {
        let plan = UninstallPlan(
            app: app(path: "/Applications/Example.app"), includeApp: false,
            leftovers: [leftover("/a/b"), leftover("/a/b/c/d"), leftover("/a/b/c")]
        )

        #expect(plan.leftovers.map(\.path) == ["/a/b/c/d", "/a/b/c", "/a/b"])
    }
}
