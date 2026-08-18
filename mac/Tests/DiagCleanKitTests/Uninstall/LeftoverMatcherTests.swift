import Foundation
import Testing
@testable import DiagCleanKit

/// Matching decides what a technician is shown and invited to remove, so these tests
/// are written as a set of claims about what must and must not be offered. Several
/// cases are taken verbatim from a real machine, where the CLI's substring matching
/// produces genuinely dangerous results.
@Suite("LeftoverMatcher")
struct LeftoverMatcherTests {

    private func match(
        _ entryName: String,
        in location: String = "Application Support",
        app: String,
        id: String
    ) -> MatchConfidence? {
        LeftoverMatcher.match(entryName: entryName, location: location, appName: app, bundleIdentifier: id)
    }

    // MARK: - The reason this exists

    /// The headline case. On the machine this was developed against, uninstalling an app
    /// called "Flow" under substring matching offers eight of Apple's containers —
    /// Shortcuts, WorkflowKit, the Intelligence runtime — because each contains "flow".
    @Test("never matches Apple's own containers, however well the letters line up")
    func neverMatchesAppleSoftware() {
        let appleEntries = [
            "com.apple.WorkflowKit.ShortcutsIntents",
            "com.apple.WorkflowUI.AddShortcutExtension",
            "com.apple.intelligenceflow.IntelligenceFlowRuntime",
            "com.apple.shortcuts.Run-Workflow",
        ]

        for entry in appleEntries {
            #expect(
                match(entry, in: "Containers", app: "Flow", id: "com.example.flow") == nil,
                "\(entry) belongs to macOS and must never be offered"
            )
        }
    }

    @Test("never matches Apple's iWork containers when removing an app called Numbers")
    func neverMatchesIWork() {
        #expect(match("com.apple.iWork.Numbers", in: "Containers", app: "Numbers", id: "com.example.numbers") == nil)
    }

    /// A substring match would let a four-letter app name reach an unrelated vendor's
    /// files. Anchoring plus a required separator is what prevents it.
    @Test("does not let a short app name reach a longer unrelated one")
    func doesNotMatchOnBareSubstring() {
        #expect(match("BeardedSpice", app: "Bear", id: "net.shinyfrog.bear") == nil)
        #expect(match("com.beardedspice.player", app: "Bear", id: "net.shinyfrog.bear") == nil)
        #expect(match("NotesWidgetHelper", app: "Notes", id: "com.example.notes") == nil)
    }

    @Test("ignores app names too short to anchor anything safely")
    func ignoresVeryShortNames() {
        #expect(match("Go Development Kit", app: "Go", id: "com.example.go") == nil)
    }

    // MARK: - Confident matches

    @Test("matches an entry named exactly for the bundle identifier")
    func matchesExactIdentifier() {
        #expect(match("com.docker.docker", in: "Containers", app: "Docker", id: "com.docker.docker") == .confident)
    }

    @Test("matches a child namespace of the bundle identifier")
    func matchesIdentifierNamespace() {
        #expect(match("com.brave.Browser.helper", app: "Brave Browser", id: "com.brave.Browser") == .confident)
        #expect(match("com.brave.Browser.nightly.helper", app: "Brave Browser", id: "com.brave.Browser") == .confident)
    }

    @Test("matches the per-app state files macOS names after the identifier")
    func matchesIdentifierSuffixes() {
        #expect(match("fun.ferret.Ferret.plist", in: "Preferences", app: "Ferret", id: "fun.ferret.Ferret") == .confident)
        #expect(match("fun.ferret.Ferret.savedState", in: "Saved Application State", app: "Ferret", id: "fun.ferret.Ferret") == .confident)
        #expect(match("fun.ferret.Ferret.binarycookies", in: "HTTPStorages", app: "Ferret", id: "fun.ferret.Ferret") == .confident)
    }

    @Test("matches the app's plain name where apps conventionally use one")
    func matchesPlainNameInConventionalLocations() {
        #expect(match("Ferret", in: "Application Support", app: "Ferret", id: "fun.ferret.Ferret") == .confident)
        #expect(match("Ferret", in: "Caches", app: "Ferret", id: "fun.ferret.Ferret") == .confident)
        #expect(match("ferret", in: "Logs", app: "Ferret", id: "fun.ferret.Ferret") == .confident)
    }

    /// In Preferences and Containers everything is identifier-shaped, so a bare display
    /// name there is a coincidence rather than the convention — demoted, not trusted.
    @Test("demotes a plain-name match found where names are normally identifiers")
    func demotesPlainNameInIdentifierLocations() {
        #expect(match("Ferret", in: "Containers", app: "Ferret", id: "fun.ferret.Ferret") == .likely)
        #expect(match("Ferret", in: "Preferences", app: "Ferret", id: "fun.ferret.Ferret") == .likely)
    }

    // MARK: - Likely matches

    @Test("offers a name-plus-separator match, unticked")
    func offersNamePrefixAsLikely() {
        #expect(match("Docker Desktop", app: "Docker", id: "com.docker.docker") == .likely)
        #expect(match("Ferret-Helper", app: "Ferret", id: "fun.ferret.Ferret") == .likely)
        #expect(match("Ferret_data", app: "Ferret", id: "fun.ferret.Ferret") == .likely)
    }

    /// A group container's namespace is usually an ancestor of the app's identifier, and
    /// ancestors are shared: `group.com.microsoft` belongs to Word and Excel alike, so
    /// removing it while uninstalling one would break the other.
    @Test("treats a shared group container as a judgement call, not a certainty")
    func groupContainerAncestorIsLikely() {
        #expect(match("group.com.docker", in: "Group Containers", app: "Docker", id: "com.docker.docker") == .likely)
        #expect(match("group.com.microsoft", in: "Group Containers", app: "Word", id: "com.microsoft.Word") == .likely)
    }

    @Test("matches a group container named exactly for the app")
    func groupContainerExactIsConfident() {
        #expect(match("group.com.docker.docker", in: "Group Containers", app: "Docker", id: "com.docker.docker") == .confident)
        #expect(match("U355UULQVV.com.docker.docker", in: "Group Containers", app: "Docker", id: "com.docker.docker") == .confident)
    }

    @Test("only confident matches are ticked by default")
    func defaultSelection() {
        #expect(MatchConfidence.confident.isSelectedByDefault)
        #expect(!MatchConfidence.likely.isSelectedByDefault)
    }

    // MARK: - Degenerate input

    @Test("an app with no bundle identifier matches nothing on identity alone")
    func emptyIdentifierMatchesNothing() {
        #expect(match("com.example.thing", app: "Thing", id: "") == nil)
    }

    @Test("matching is case-insensitive, as the filesystem is")
    func caseInsensitive() {
        #expect(match("COM.DOCKER.DOCKER", in: "Containers", app: "Docker", id: "com.docker.docker") == .confident)
    }
}
