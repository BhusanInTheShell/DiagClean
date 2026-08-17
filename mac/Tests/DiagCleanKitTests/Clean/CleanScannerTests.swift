import Foundation
import Testing
@testable import DiagCleanKit

private struct FixedTarget: CleanTarget {
    let category: CleanCategory
    let pathGuard: PathGuard
    let paths: [String]

    func candidates() -> [Candidate] {
        paths.map { Candidate(path: $0, ownerLabel: "Test") }
    }
}

@Suite("CleanScanner")
struct CleanScannerTests {

    @Test("measures each item and totals the scan")
    func measuresItems() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let a = try workspace.makeFile("caches/a/blob", bytes: 8192)
        let b = try workspace.makeFile("caches/b.bin", bytes: 4096)

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [(a as NSString).deletingLastPathComponent, b]
        )])

        let scan = try await scanner.scan()

        #expect(scan.itemCount == 2)
        // Allocated size rounds up to whole blocks, so assert a floor rather than an
        // exact figure — the point is that real bytes were measured, not zero.
        #expect(scan.totalBytes >= 12288)
    }

    /// Scanning must never be able to modify anything. This is what makes it safe to
    /// run automatically when the screen opens, which is in turn what makes the app
    /// feel like it is already working rather than waiting to be told to.
    @Test("a scan leaves every candidate on disk")
    func scanIsReadOnly() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let file = try workspace.makeFile("caches/a.bin", bytes: 2048)

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [file]
        )])

        _ = try await scanner.scan()

        #expect(workspace.exists(file))
    }

    @Test("a guard-refused candidate is reported as skipped, never as an item")
    func refusedCandidatesAreSkippedVisibly() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let personal = try workspace.makeFile("caches/personal/photo.jpg", bytes: 4096)

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(
                allowedRoots: [root],
                protectedPaths: [workspace.path("caches", "personal")]
            ),
            paths: [personal]
        )])

        let scan = try await scanner.scan()

        #expect(scan.itemCount == 0)
        #expect(scan.categories[0].skipped.count == 1)
        #expect(scan.categories[0].skipped[0].reason.contains("protected"))
    }

    @Test("drops zero-byte candidates rather than padding the list with nothing")
    func dropsEmptyCandidates() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let empty = try workspace.makeDirectory("caches", "empty")

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [empty]
        )])

        let scan = try await scanner.scan()

        #expect(scan.itemCount == 0)
    }

    @Test("sizes a directory without following symlinks out of it")
    func doesNotSizeThroughSymlinks() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        try workspace.makeFile("elsewhere/huge.bin", bytes: 1_000_000)
        let cache = try workspace.makeDirectory("caches", "com.example.app")
        try workspace.makeFile("caches/com.example.app/small.bin", bytes: 1024)
        try workspace.makeSymlink("caches/com.example.app/link-to-huge", to: workspace.path("elsewhere"))

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [cache]
        )])

        let scan = try await scanner.scan()

        #expect(scan.totalBytes < 100_000, "a link must not inflate a cache's reported size")
    }

    @Test("sorts items largest first, because that is the decision being made")
    func sortsBySize() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let small = try workspace.makeFile("caches/small.bin", bytes: 1024)
        let large = try workspace.makeFile("caches/large.bin", bytes: 512_000)

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [small, large]
        )])

        let scan = try await scanner.scan()

        #expect(scan.allItems.map(\.path) == [large, small])
    }

    @Test("a cancelled scan throws rather than returning half a preview")
    func cancellationThrows() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        var paths: [String] = []
        for index in 0..<200 {
            paths.append(try workspace.makeFile("caches/file-\(index).bin", bytes: 1024))
        }

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: paths
        )])

        let task = Task { try await scanner.scan() }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("items carry the canonical path, so the executor acts where the guard looked")
    func itemsCarryCanonicalPaths() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let real = try workspace.makeFile("caches/thing.bin", bytes: 2048)
        let messy = (root as NSString).appendingPathComponent("./thing.bin")

        let scanner = CleanScanner(targets: [FixedTarget(
            category: .applicationCaches,
            pathGuard: PathGuard(allowedRoots: [root], protectedPaths: []),
            paths: [messy]
        )])

        let scan = try await scanner.scan()

        #expect(scan.allItems[0].path == real)
    }
}

@Suite("RunLog")
struct RunLogTests {

    @Test("records what was planned, what was removed and why anything failed")
    func recordsRun() throws {
        let workspace = try TempWorkspace()
        let logDirectory = try workspace.makeDirectory("logs")

        let item = CleanItem(
            path: "/tmp/example/cache",
            category: .applicationCaches,
            ownerLabel: "Example",
            sizeBytes: 2048,
            isDirectory: true,
            lastModified: nil
        )
        let report = CleanReport(
            bytesFreed: 0,
            itemsRemoved: 0,
            failures: [CleanFailure(path: "/tmp/example/cache", reason: "in use")],
            wasCancelled: false,
            startedAt: Date(),
            finishedAt: Date()
        )

        let url = RunLog(directory: logDirectory).record(plan: CleanPlan(items: [item]), report: report)

        let contents = try String(contentsOfFile: try #require(url).path, encoding: .utf8)
        #expect(contents.contains("/tmp/example/cache"))
        #expect(contents.contains("FAILED"))
        #expect(contents.contains("in use"))
    }

    @Test("appends rather than overwriting, so a day's runs accumulate")
    func appendsAcrossRuns() throws {
        let workspace = try TempWorkspace()
        let logDirectory = try workspace.makeDirectory("logs")
        let log = RunLog(directory: logDirectory)

        let report = CleanReport(
            bytesFreed: 10, itemsRemoved: 1, failures: [],
            wasCancelled: false, startedAt: Date(), finishedAt: Date()
        )
        let plan = CleanPlan(items: [CleanItem(
            path: "/tmp/a", category: .temporaryFiles, ownerLabel: "T",
            sizeBytes: 10, isDirectory: false, lastModified: nil
        )])

        log.record(plan: plan, report: report)
        let url = try #require(log.record(plan: plan, report: report))

        let contents = try String(contentsOfFile: url.path, encoding: .utf8)
        #expect(contents.components(separatedBy: "---- Clean run").count == 3)
    }

    @Test("notes when a run was cancelled partway")
    func notesCancellation() throws {
        let workspace = try TempWorkspace()
        let logDirectory = try workspace.makeDirectory("logs")

        let report = CleanReport(
            bytesFreed: 5, itemsRemoved: 1, failures: [],
            wasCancelled: true, startedAt: Date(), finishedAt: Date()
        )
        let url = try #require(RunLog(directory: logDirectory).record(plan: CleanPlan(items: []), report: report))

        let contents = try String(contentsOfFile: url.path, encoding: .utf8)
        #expect(contents.contains("cancelled partway"))
    }
}
