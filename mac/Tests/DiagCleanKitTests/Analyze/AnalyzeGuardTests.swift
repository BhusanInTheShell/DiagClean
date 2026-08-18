import Foundation
import Testing
@testable import DiagCleanKit

/// Analyze is the only feature that can reach anywhere on the disk, so the question
/// these tests answer is: what can a disk browser never be allowed to throw away?
@Suite("AnalyzeGuard")
struct AnalyzeGuardTests {

    // MARK: - Never removable

    @Test("refuses the root of a volume")
    func refusesVolumeRoot() {
        let sut = AnalyzeGuard(user: UserPaths(home: "/Users/example"))
        #expect(sut.decide("/").denial == .volumeRoot)
    }

    @Test("refuses the home folder itself")
    func refusesHomeFolder() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(home).denial == .homeFolder)
    }

    @Test("refuses macOS's own directories")
    func refusesSystemPaths() {
        let sut = AnalyzeGuard(user: UserPaths(home: "/Users/example"))

        for path in ["/System", "/System/Library/Frameworks", "/usr/bin", "/bin", "/Library/Fonts"] {
            guard case .systemPath = sut.decide(path).denial else {
                Issue.record("\(path) belongs to macOS and must be refused")
                return
            }
        }
    }

    @Test("refuses keys and credentials")
    func refusesCredentials() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        try workspace.makeDirectory("home", "Library", "Keychains")
        try workspace.makeFile("home/.ssh/id_ed25519")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide((home as NSString).appendingPathComponent("Library/Keychains")).denial == .credentials)
        #expect(sut.decide((home as NSString).appendingPathComponent(".ssh/id_ed25519")).denial == .credentials)
    }

    @Test("refuses DiagClean's own audit trail")
    func refusesAuditTrail() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let logs = try workspace.makeDirectory("home", "Library", "Application Support", "DiagClean", "logs")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(logs).denial == .auditTrail)
    }

    /// Trashing a bundle from a disk browser would leave its caches, preferences and
    /// containers behind — precisely the mess Uninstall exists to prevent.
    @Test("refuses an installed application and points at Uninstall instead")
    func refusesApplicationBundle() {
        let sut = AnalyzeGuard(user: UserPaths(home: "/Users/example"))

        guard case .applicationBundle(let name) = sut.decide("/Applications/Docker.app").denial else {
            Issue.record("an app bundle must be refused here")
            return
        }
        #expect(name == "Docker.app")
        #expect(sut.decide("/Applications/Docker.app").denial?.explanation.contains("Uninstall") == true)
    }

    @Test("refuses a symbolic link rather than following it")
    func refusesSymlink() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        try workspace.makeDirectory("home", "real")
        let link = try workspace.makeSymlink("home/link", to: workspace.path("home", "real"))
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(link).denial == .symbolicLink)
    }

    // MARK: - The personal folders

    /// The container cannot go, its contents can. Finding a forgotten 40 GB export in
    /// Movies is a real reason to use this tool; losing Movies entirely is not.
    @Test("refuses a personal folder itself but allows what is inside it")
    func personalFolderItselfVersusContents() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let documents = try workspace.makeDirectory("home", "Documents")
        let file = try workspace.makeFile("home/Documents/huge-export.mov")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(documents).denial == .personalFolderItself("Documents"))
        #expect(sut.decide(file).isAllowed)
    }

    /// Found by driving the real app: `~/Library` was offered for removal at 46 GB.
    /// Trashing it takes every app's preferences, containers and keychains with it. The
    /// system-wide `/Library` was already covered; its per-user twin was not.
    @Test("refuses the user's Library folder itself but allows what is inside it")
    func refusesUserLibraryItself() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let library = try workspace.makeDirectory("home", "Library")
        let cache = try workspace.makeDirectory("home", "Library", "Caches", "com.example.app")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(library).denial == .essentialFolderItself("Library"))
        #expect(sut.decide(cache).isAllowed, "clearing a cache inside Library stays perfectly ordinary")
    }

    @Test("refuses the user's Applications folder itself")
    func refusesUserApplicationsItself() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let apps = try workspace.makeDirectory("home", "Applications")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(apps).denial == .essentialFolderItself("Applications"))
    }

    @Test("flags anything inside a personal folder as personal data")
    func flagsPersonalContents() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let file = try workspace.makeFile("home/Pictures/holiday/DSC_0001.raw")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        // The expected path is canonicalised, not merely standardized: standardizing
        // strips /private and would compare a different spelling of the same file.
        #expect(sut.decide(file) == .allowed(
            canonicalPath: PathGuard.canonicalize(file, using: LivePathResolver()),
            sensitivity: .personal(container: "Pictures")
        ))
    }

    /// A synced file removed here disappears from every device on the account, which
    /// makes it meaningfully worse than a local mistake.
    @Test("flags cloud-synced files as personal")
    func flagsCloudContents() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let file = try workspace.makeFile("home/Library/Mobile Documents/doc.pages")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        guard case .allowed(_, .personal(let container)) = sut.decide(file) else {
            Issue.record("iCloud contents must be flagged as personal")
            return
        }
        #expect(container == "iCloud Drive")
    }

    // MARK: - Ordinary removals

    @Test("allows an ordinary cache directory with no special warning")
    func allowsOrdinaryPath() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let cache = try workspace.makeDirectory("home", "Library", "Caches", "com.example.app")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide(cache) == .allowed(
            canonicalPath: PathGuard.canonicalize(cache, using: LivePathResolver()), sensitivity: .normal
        ))
    }

    @Test("refuses something that is no longer there")
    func refusesMissing() throws {
        let workspace = try TempWorkspace()
        let home = try workspace.makeDirectory("home")
        let sut = AnalyzeGuard(user: UserPaths(home: home))

        #expect(sut.decide((home as NSString).appendingPathComponent("gone/child")).denial == .doesNotExist)
    }
}
