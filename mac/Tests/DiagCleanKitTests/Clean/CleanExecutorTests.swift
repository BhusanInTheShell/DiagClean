import Foundation
import Testing
@testable import DiagCleanKit

/// A target that offers exactly the paths a test hands it, guarded by a real
/// `PathGuard`. The guard is never faked — the point of most of these tests is that the
/// executor consults it a second time, so a stubbed guard would test nothing.
private struct FixedTarget: CleanTarget {
    let category: CleanCategory
    let pathGuard: PathGuard
    let paths: [String]

    func candidates() -> [Candidate] {
        paths.map { Candidate(path: $0, ownerLabel: "Test") }
    }
}

private func item(
    _ path: String,
    category: CleanCategory = .applicationCaches,
    size: Int64 = 1024
) -> CleanItem {
    CleanItem(
        path: path,
        category: category,
        ownerLabel: "Test",
        sizeBytes: size,
        isDirectory: false,
        lastModified: nil
    )
}

@Suite("CleanExecutor")
struct CleanExecutorTests {

    @Test("removes the files in the plan and reports what it freed")
    func removesPlannedItems() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let a = try workspace.makeFile("caches/a.bin", bytes: 2048)
        let b = try workspace.makeFile("caches/b.bin", bytes: 4096)

        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [a, b]
        )
        let plan = CleanPlan(items: [item(a, size: 2048), item(b, size: 4096)])

        let report = await CleanExecutor(targets: [target]).execute(plan: plan)

        #expect(report.itemsRemoved == 2)
        #expect(report.bytesFreed == 6144)
        #expect(report.failures.isEmpty)
        #expect(!workspace.exists(a))
        #expect(!workspace.exists(b))
    }

    /// The core safety property. A plan is built from a scan that may be minutes old by
    /// the time a technician has read it and confirmed; if something protected has
    /// moved into place since, the executor must catch it rather than trust the plan.
    @Test("re-checks the guard at removal time and refuses a path the scan would no longer allow")
    func reChecksGuardBeforeRemoving() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let allowed = try workspace.makeFile("caches/allowed.bin")
        let nowProtected = try workspace.makeFile("caches/personal/photo.jpg")

        // The plan contains both, as though the scan ran before this path became
        // protected. The guard the executor uses protects it now.
        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(
                allowedRoots: [root],
                protectedPaths: [workspace.path("caches", "personal")]
            ),
            paths: []
        )
        let plan = CleanPlan(items: [item(allowed), item(nowProtected)])

        let report = await CleanExecutor(targets: [target]).execute(plan: plan)

        #expect(report.itemsRemoved == 1)
        #expect(!workspace.exists(allowed))
        #expect(workspace.exists(nowProtected), "a protected file must survive even when it is in the plan")
        #expect(report.failures.count == 1)
        #expect(report.failures[0].reason.contains("blocked at removal time"))
    }

    @Test("refuses a plan item that names a category with no registered guard")
    func refusesUnguardedCategory() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let file = try workspace.makeFile("caches/a.bin")

        // Executor knows about applicationCaches only; the plan item claims to be a
        // temporary file. No guard, no authority, no deletion.
        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: []
        )
        let plan = CleanPlan(items: [item(file, category: .temporaryFiles)])

        let report = await CleanExecutor(targets: [target]).execute(plan: plan)

        #expect(report.itemsRemoved == 0)
        #expect(workspace.exists(file))
        #expect(report.failures[0].reason.contains("no guard is registered"))
    }

    @Test("never follows a symlink out of an allowed root")
    func refusesSymlink() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let realFile = try workspace.makeFile("documents/thesis.txt")
        let link = try workspace.makeSymlink("caches/looks-like-junk", to: realFile)

        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: []
        )
        let plan = CleanPlan(items: [item(link)])

        let report = await CleanExecutor(targets: [target]).execute(plan: plan)

        #expect(report.itemsRemoved == 0)
        #expect(workspace.exists(realFile), "the link's target must be untouched")
        #expect(report.failures[0].reason.contains("symbolic link"))
    }

    @Test("counts an item that vanished before removal as freed, not failed")
    func treatsAlreadyGoneAsSuccess() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let ghost = (root as NSString).appendingPathComponent("cleared-itself.bin")

        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: []
        )
        let plan = CleanPlan(items: [item(ghost)])

        let report = await CleanExecutor(targets: [target]).execute(plan: plan)

        #expect(report.failures.isEmpty, "a browser clearing its own cache mid-run is not an error")
        #expect(report.itemsRemoved == 1)
    }

    @Test("removes a directory and everything in it")
    func removesDirectoryTree() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let tree = try workspace.makeDirectory("caches", "com.example.app")
        try workspace.makeFile("caches/com.example.app/nested/deep/file.bin")

        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: []
        )
        let plan = CleanPlan(items: [item(tree)])

        let report = await CleanExecutor(targets: [target]).execute(plan: plan)

        #expect(report.itemsRemoved == 1)
        #expect(!workspace.exists(tree))
    }

    @Test("a cancelled run stops early and reports itself as cancelled")
    func honoursCancellation() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        var paths: [String] = []
        for index in 0..<50 {
            paths.append(try workspace.makeFile("caches/file-\(index).bin"))
        }

        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: []
        )
        let plan = CleanPlan(items: paths.map { item($0) })
        let executor = CleanExecutor(targets: [target])

        let task = Task { await executor.execute(plan: plan) }
        task.cancel()
        let report = await task.value

        #expect(report.wasCancelled)
        #expect(report.itemsRemoved < plan.itemCount)
    }

    @Test("reports progress once per item, with a running total")
    func reportsProgress() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let a = try workspace.makeFile("caches/a.bin")
        let b = try workspace.makeFile("caches/b.bin")

        let target = FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: []
        )
        let plan = CleanPlan(items: [item(a, size: 100), item(b, size: 200)])

        let collected = Mutex<[CleanProgress]>([])
        _ = await CleanExecutor(targets: [target]).execute(plan: plan) { progress in
            collected.withLock { $0.append(progress) }
        }

        let updates = collected.withLock { $0 }
        #expect(updates.count == 2)
        #expect(updates.last?.itemsCompleted == 2)
        #expect(updates.last?.bytesFreed == 300)
    }

    /// A plan that somehow contains both a directory and something inside it must not
    /// report the nested bytes twice. Ordering deepest-first makes the child's removal
    /// the one that counts.
    @Test("orders nested paths deepest-first")
    func ordersDeepestFirst() {
        let plan = CleanPlan(items: [
            item("/a/b"),
            item("/a/b/c/d"),
            item("/a/b/c"),
        ])

        #expect(plan.items.map(\.path) == ["/a/b/c/d", "/a/b/c", "/a/b"])
    }
}

/// Minimal lock for collecting callback output from a `@Sendable` closure in tests.
final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
