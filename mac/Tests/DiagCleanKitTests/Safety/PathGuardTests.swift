import Foundation
import Testing
@testable import DiagCleanKit

/// The guard is the single point where a bug anywhere else in DiagClean turns into
/// somebody's lost data, so these tests are the ones worth being obsessive about.
@Suite("PathGuard")
struct PathGuardTests {

    // MARK: - The basic contract

    @Test("allows a strict descendant of an allowed root")
    func allowsDescendant() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let item = try workspace.makeDirectory("caches", "com.example.app")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])

        #expect(sut.decide(item).isAllowed)
    }

    @Test("refuses anything outside every allowed root")
    func refusesOutsider() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let outsider = try workspace.makeDirectory("documents", "taxes")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])

        #expect(sut.decide(outsider).denial == .outsideAllowedRoots)
    }

    /// The CLI's guard treats a path equal to an allowed root as allowed, so a bug that
    /// produced the bare root would be permitted to delete the entire root. Nothing may
    /// name a root itself.
    @Test("refuses an allowed root itself, not just paths outside it")
    func refusesRootItself() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])

        guard case .isAllowedRootItself = sut.decide(root).denial else {
            Issue.record("expected the root itself to be refused, got \(sut.decide(root))")
            return
        }
    }

    @Test("refuses the filesystem root outright")
    func refusesFilesystemRoot() {
        let sut = PathGuard(allowedRoots: ["/"], protectedPaths: [])
        #expect(sut.decide("/").denial == .filesystemRoot)
    }

    @Test("refuses relative paths")
    func refusesRelativePaths() {
        let sut = PathGuard(allowedRoots: ["/tmp"], protectedPaths: [])
        #expect(sut.decide("some/relative/path").denial == .notAbsolute)
    }

    // MARK: - Protected paths win

    @Test("a protected path is refused even when it sits inside an allowed root")
    func protectedBeatsAllowed() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("home")
        let documents = try workspace.makeDirectory("home", "Documents")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [documents])

        guard case .protectedPath = sut.decide(documents).denial else {
            Issue.record("expected a protected-path denial")
            return
        }
    }

    @Test("descendants of a protected path are refused too")
    func protectedIsInherited() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("home")
        let documents = try workspace.makeDirectory("home", "Documents")
        let file = try workspace.makeFile("home/Documents/notes/tax-return.pdf")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [documents])

        guard case .protectedPath = sut.decide(file).denial else {
            Issue.record("expected a file inside a protected directory to be refused")
            return
        }
    }

    /// The bug this exists to prevent: the CLI compares paths ordinally on macOS, but
    /// the default root volume is case-insensitive APFS. `~/documents` and `~/Documents`
    /// are the same directory on disk, and an ordinal comparison recognises only one of
    /// them as protected.
    @Test("protected matching ignores case, because the macOS boot volume does")
    func protectedMatchingIsCaseInsensitive() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("home")
        let documents = try workspace.makeDirectory("home", "Documents")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [documents])
        let lowercased = (workspace.root as NSString).appendingPathComponent("home/documents")

        guard case .protectedPath = sut.decide(lowercased).denial else {
            Issue.record("a differently-cased spelling of a protected path must still be protected")
            return
        }
    }

    @Test("protected matching survives Unicode composition differences")
    func protectedMatchingIsNormalizationInsensitive() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("home")
        // "Café" written with a precomposed é, then addressed with a combining accent.
        let precomposed = try workspace.makeDirectory("home", "Caf\u{00E9}")
        let decomposed = (workspace.root as NSString).appendingPathComponent("home/Cafe\u{0301}")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [precomposed])

        guard case .protectedPath = sut.decide(decomposed).denial else {
            Issue.record("both spellings name the same directory and must both be protected")
            return
        }
    }

    @Test("a protected path that does not exist yet is still protected")
    func protectedPathNeedNotExist() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let notYetCreated = (root as NSString).appendingPathComponent("future")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [notYetCreated])

        guard case .protectedPath = sut.decide(notYetCreated).denial else {
            Issue.record("realpath cannot resolve a path that does not exist; that must not un-protect it")
            return
        }
    }

    // MARK: - Symlinks

    @Test("refuses a symlink outright rather than following it")
    func refusesSymlink() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        try workspace.makeDirectory("documents")
        let link = try workspace.makeSymlink("caches/innocent-looking", to: workspace.path("documents"))

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])

        #expect(sut.decide(link).denial == .symbolicLink)
    }

    /// The escape this closes: an *ancestor* is a link out of the allowed root. The path
    /// string looks like it is inside `caches`, and it isn't.
    @Test("refuses a path whose parent directory links out of the allowed root")
    func refusesEscapeThroughLinkedParent() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        try workspace.makeDirectory("elsewhere", "real-data")
        try workspace.makeSymlink("caches/looks-local", to: workspace.path("elsewhere"))

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])
        let escaped = (root as NSString).appendingPathComponent("looks-local/real-data")

        #expect(sut.decide(escaped).denial == .outsideAllowedRoots)
    }

    @Test("a protected directory reached through a symlinked parent is still protected")
    func protectedThroughLinkedParent() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let documents = try workspace.makeDirectory("home", "Documents")
        try workspace.makeSymlink("caches/shortcut", to: workspace.path("home"))

        let sut = PathGuard(allowedRoots: [root, workspace.path("home")], protectedPaths: [documents])
        let viaLink = (root as NSString).appendingPathComponent("shortcut/Documents")

        guard case .protectedPath = sut.decide(viaLink).denial else {
            Issue.record("the guard must judge where a path really is, not how it is spelled")
            return
        }
    }

    // MARK: - Path arithmetic

    @Test("refuses a traversal that climbs out of the allowed root")
    func refusesDotDotEscape() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        try workspace.makeDirectory("documents")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])
        let traversal = (root as NSString).appendingPathComponent("../documents")

        #expect(sut.decide(traversal).denial == .outsideAllowedRoots)
    }

    @Test("an allowed root reached through a symlink still matches paths inside it")
    func canonicalisesAllowedRoots() throws {
        let workspace = try TempWorkspace()
        let real = try workspace.makeDirectory("real-caches")
        let item = try workspace.makeDirectory("real-caches", "com.example.app")
        let linkedRoot = try workspace.makeSymlink("linked-caches", to: real)

        // The guard is configured with the *link*; the candidate arrives by its real
        // path. Both must resolve to the same place, or the guard rejects legitimate
        // work and the technician sees an empty scan with no explanation.
        let sut = PathGuard(allowedRoots: [linkedRoot], protectedPaths: [])

        #expect(sut.decide(item).isAllowed)
    }

    @Test("reports the canonical path so callers act on the resolved location")
    func reportsCanonicalPath() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")
        let item = try workspace.makeDirectory("caches", "thing")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])
        let messy = (root as NSString).appendingPathComponent("./thing/")

        #expect(sut.decide(messy) == .allowed(canonicalPath: item))
    }

    @Test("refuses a path whose parent does not exist")
    func refusesUnresolvableParent() throws {
        let workspace = try TempWorkspace()
        let root = try workspace.makeDirectory("caches")

        let sut = PathGuard(allowedRoots: [root], protectedPaths: [])
        let ghost = (root as NSString).appendingPathComponent("no-such-dir/child")

        guard case .unresolvable = sut.decide(ghost).denial else {
            Issue.record("expected an unresolvable-parent denial")
            return
        }
    }

    @Test("an empty allowed-roots list permits nothing at all")
    func emptyAllowedRootsPermitsNothing() throws {
        let workspace = try TempWorkspace()
        let item = try workspace.makeDirectory("anything")

        let sut = PathGuard(allowedRoots: [], protectedPaths: [])

        #expect(sut.decide(item).denial == .outsideAllowedRoots)
    }
}
