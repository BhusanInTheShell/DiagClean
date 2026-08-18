import Foundation
import Testing
@testable import DiagCleanKit

@Suite("DirectoryAnalyzer")
struct DirectoryAnalyzerTests {

    @Test("measures each child's recursive size and sorts largest first")
    func measuresAndSorts() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("root")
        try workspace.makeFile("root/small/a.bin", bytes: 1024)
        try workspace.makeFile("root/large/nested/deep/b.bin", bytes: 512_000)

        let listing = try await DirectoryAnalyzer().listing(of: root)

        #expect(listing.entries.map(\.name) == ["large", "small"])
        #expect(listing.entries[0].sizeBytes > listing.entries[1].sizeBytes)
        #expect(listing.entries.allSatisfy { $0.isDirectory })
    }

    @Test("reports each entry as it finishes rather than only at the end")
    func streamsEntries() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("root")
        for index in 0..<8 {
            try workspace.makeFile("root/file-\(index).bin", bytes: 2048)
        }

        let streamed = Mutex<[String]>([])
        let listing = try await DirectoryAnalyzer().listing(of: root) { entry in
            streamed.withLock { $0.append(entry.name) }
        }

        #expect(streamed.withLock { $0.count } == listing.entries.count)
    }

    /// A link into a huge tree must not report bytes that removing the link would not
    /// actually free.
    @Test("lists a symlink at its own size without following it")
    func doesNotFollowSymlinks() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("root")
        try workspace.makeFile("elsewhere/huge.bin", bytes: 1_000_000)
        try workspace.makeSymlink("root/link", to: workspace.path("elsewhere"))

        let listing = try await DirectoryAnalyzer().listing(of: root)

        let link = try #require(listing.entries.first { $0.name == "link" })
        #expect(link.sizeBytes == 0)
        #expect(!link.isDirectory)
    }

    @Test("reports an unreadable directory rather than pretending it is empty")
    func reportsUnreadable() async throws {
        let listing = try await DirectoryAnalyzer().listing(of: "/no/such/directory")

        #expect(listing.entries.isEmpty)
        #expect(listing.unreadableCount == 1)
    }

    @Test("distinguishes files from directories")
    func classifiesEntries() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("root")
        try workspace.makeFile("root/loose.bin", bytes: 1024)
        try workspace.makeDirectory("root", "folder")

        let listing = try await DirectoryAnalyzer().listing(of: root)

        #expect(listing.entries.first { $0.name == "loose.bin" }?.isDirectory == false)
        #expect(listing.entries.first { $0.name == "folder" }?.isDirectory == true)
    }

    @Test("a cancelled listing throws rather than returning half a picture")
    func cancellationThrows() async throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("root")
        for index in 0..<200 {
            try workspace.makeFile("root/dir-\(index)/file.bin", bytes: 1024)
        }

        let analyzer = DirectoryAnalyzer()
        let task = Task { try await analyzer.listing(of: root) }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("builds a breadcrumb from the volume root down")
    func buildsBreadcrumb() {
        let crumbs = DirectoryAnalyzer.breadcrumb(for: "/Users/example/Library/Caches")

        #expect(crumbs.map(\.name) == ["Macintosh HD", "Users", "example", "Library", "Caches"])
        #expect(crumbs.last?.path == "/Users/example/Library/Caches")
        #expect(crumbs.first?.path == "/")
    }
}

@Suite("AnalyzeRemover")
struct AnalyzeRemoverTests {

    private func entry(_ path: String, size: Int64 = 1024) -> DiskEntry {
        DiskEntry(path: path, name: (path as NSString).lastPathComponent,
                  sizeBytes: size, isDirectory: false, lastModified: nil)
    }

    @Test("refuses a path the guard would not allow, at removal time")
    func refusesGuardedPath() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let documents = try workspace.makeDirectory("home", "Documents")

        let remover = AnalyzeRemover(analyzeGuard: AnalyzeGuard(user: UserPaths(home: home)))
        let report = remover.remove(entry(documents))

        #expect(!report.succeeded)
        #expect(report.failure?.contains("blocked at removal time") == true)
        #expect(workspace.exists(documents))
    }

    @Test("reports an item that is already gone rather than claiming success")
    func reportsMissing() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let ghost = (home as NSString).appendingPathComponent("Library/Caches/gone")

        let remover = AnalyzeRemover(analyzeGuard: AnalyzeGuard(user: UserPaths(home: home)))
        let report = remover.remove(entry(ghost))

        #expect(!report.succeeded)
    }
}
