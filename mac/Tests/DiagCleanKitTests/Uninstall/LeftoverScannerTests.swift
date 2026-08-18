import Foundation
import Testing
@testable import DiagCleanKit

@Suite("LeftoverScanner")
struct LeftoverScannerTests {

    private func app(name: String, id: String) -> InstalledApp {
        InstalledApp(
            path: "/Applications/\(name).app", name: name, bundleIdentifier: id,
            version: "1.0", sizeBytes: 0, lastUsed: nil, isAppleSoftware: false
        )
    }

    @Test("finds an app's files across the Library directories it scatters into")
    func findsLeftoversAcrossLocations() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Application Support/Ferret/state.db", bytes: 4096)
        try workspace.makeFile("home/Library/Preferences/fun.ferret.Ferret.plist", bytes: 1024)
        try workspace.makeFile("home/Library/Caches/fun.ferret.Ferret/blob", bytes: 2048)

        let scanner = LeftoverScanner(user: user)
        let scan = try await scanner.scan(app: app(name: "Ferret", id: "fun.ferret.Ferret"))

        #expect(scan.items.count == 3)
        #expect(scan.items.allSatisfy { $0.confidence == .confident })
        #expect(scan.totalBytes > 0)
    }

    /// The scan must not modify anything, which is what makes it safe to run the moment
    /// an app is selected rather than behind a second button.
    @Test("scanning leaves every candidate on disk")
    func scanIsReadOnly() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        let file = try workspace.makeFile("home/Library/Application Support/Ferret/state.db", bytes: 1024)

        let scanner = LeftoverScanner(user: user)
        _ = try await scanner.scan(app: app(name: "Ferret", id: "fun.ferret.Ferret"))

        #expect(workspace.exists(file))
    }

    @Test("never offers another app's files")
    func ignoresUnrelatedApps() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Application Support/Ferret/state.db", bytes: 1024)
        try workspace.makeFile("home/Library/Application Support/Sketch/state.db", bytes: 1024)
        try workspace.makeFile("home/Library/Preferences/com.other.app.plist", bytes: 512)

        let scanner = LeftoverScanner(user: user)
        let scan = try await scanner.scan(app: app(name: "Ferret", id: "fun.ferret.Ferret"))

        #expect(scan.items.count == 1)
        #expect(scan.items[0].path.hasSuffix("Ferret"))
    }

    @Test("never offers Apple's containers, whatever the app is called")
    func ignoresAppleContainers() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        try workspace.makeFile("home/Library/Containers/com.apple.WorkflowKit.ShortcutsIntents/data", bytes: 4096)
        try workspace.makeFile("home/Library/Containers/com.apple.intelligenceflow.Runtime/data", bytes: 4096)

        let scanner = LeftoverScanner(user: user)
        let scan = try await scanner.scan(app: app(name: "Flow", id: "com.example.flow"))

        #expect(scan.items.isEmpty)
    }

    /// Personal directories stay off limits to Uninstall too, even though Uninstall is
    /// allowed into Containers and Preferences where Clean is not.
    @Test("still refuses the core protected paths")
    func respectsCoreProtectedPaths() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        try workspace.makeDirectory("home", "Documents")

        let scanner = LeftoverScanner(user: user)

        #expect(!scanner.pathGuard.decide(user.inHome("Documents")).isAllowed)
        #expect(!scanner.pathGuard.decide(user.inHome("Library", "Keychains")).isAllowed)
    }

    /// Uninstall must reach exactly the directories Clean is forbidden from.
    @Test("is allowed into Containers and Preferences, which Clean is not")
    func reachesAppDataDirectories() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        let container = try workspace.makeDirectory("home", "Library", "Containers", "com.example.app")
        let prefs = try workspace.makeFile("home/Library/Preferences/com.example.app.plist")

        let scanner = LeftoverScanner(user: user)

        #expect(scanner.pathGuard.decide(container).isAllowed)
        #expect(scanner.pathGuard.decide(prefs).isAllowed)

        // And the same paths are refused to Clean.
        for target in CleanScanner.defaultTargets(user: user) {
            #expect(!target.pathGuard.decide(container).isAllowed)
        }
    }

    @Test("refuses the Library roots themselves, only what is inside them")
    func refusesRootsThemselves() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        try workspace.makeDirectory("home", "Library", "Containers")

        let scanner = LeftoverScanner(user: user)

        #expect(!scanner.pathGuard.decide(user.inHome("Library", "Containers")).isAllowed)
    }

    @Test("sorts confident matches above judgement calls")
    func sortsByConfidence() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))

        // A likely match that is much larger than the confident one, to prove
        // confidence outranks size.
        try workspace.makeFile("home/Library/Application Support/Docker Desktop/big.bin", bytes: 200_000)
        try workspace.makeFile("home/Library/Containers/com.docker.docker/small.bin", bytes: 1024)

        let scanner = LeftoverScanner(user: user)
        let scan = try await scanner.scan(app: app(name: "Docker", id: "com.docker.docker"))

        #expect(scan.items.first?.confidence == .confident)
        #expect(scan.items.last?.confidence == .likely)
    }

    @Test("a cancelled scan throws rather than returning a partial list")
    func cancellationThrows() async throws {
        let workspace = try TempWorkspace()
        let user = UserPaths(home: try workspace.makeDirectory("home"))
        for index in 0..<50 {
            try workspace.makeFile("home/Library/Caches/com.example.app.\(index)/blob")
        }

        let scanner = LeftoverScanner(user: user)
        let target = app(name: "Example", id: "com.example.app")

        let task = Task { try await scanner.scan(app: target) }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
