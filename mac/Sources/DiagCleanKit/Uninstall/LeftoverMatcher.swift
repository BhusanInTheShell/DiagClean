import Foundation

/// Decides whether a file in a Library directory belongs to the app being removed.
///
/// This is the most consequential logic in Uninstall, so it is pure string work with no
/// filesystem access — every rule below is directly testable, and the tests are the
/// argument for why each one is safe.
///
/// **The CLI matches by bare substring**, against both the bundle identifier and the
/// display name. On a real machine that is not a small imprecision. Uninstalling an app
/// called `Flow` offers up eight of Apple's own containers — Shortcuts, WorkflowKit, the
/// Intelligence runtime — because every one of them contains the letters "flow".
/// Uninstalling `Numbers` reaches iWork's containers the same way.
///
/// So matching here is anchored rather than free-floating, and split into two tiers:
///
/// * **Confident** — the entry is named after the app's own bundle identifier, or is
///   exactly the app's name in a directory where apps conventionally use plain names.
///   These are ticked by default.
/// * **Likely** — a name-derived guess that is right more often than not but is
///   occasionally wrong. Shown, labelled, and *never* ticked by default, so removing one
///   is always a decision somebody made rather than one they inherited.
public enum LeftoverMatcher {

    /// Extensions macOS appends to a bundle identifier for per-app state files.
    private static let identifierSuffixes = [
        ".plist", ".savedState", ".binarycookies", ".lockfile",
    ]

    /// Directories where apps conventionally store things under a plain display name
    /// (`Application Support/Ferret`) rather than a bundle identifier. Elsewhere —
    /// Preferences, Containers, Group Containers — names are always identifier-shaped,
    /// so a bare display-name match there is a coincidence rather than a convention.
    private static let plainNameLocations: Set<String> = [
        "Application Support", "Caches", "Logs", "WebKit",
    ]

    /// Nothing owned by the operating system is ever a leftover. This single rule is
    /// what stops the `Flow` case, and it holds regardless of how good a match looks.
    public static func isSystemOwned(entryName: String) -> Bool {
        let folded = entryName.lowercased()
        return folded.hasPrefix("com.apple.") || folded == "com.apple"
    }

    /// - Parameters:
    ///   - entryName: the last path component of a candidate, e.g. `com.docker.docker`.
    ///   - location: the Library subdirectory it was found in, e.g. `Containers`.
    /// - Returns: the confidence tier, or `nil` when this is not the app's file.
    public static func match(
        entryName: String,
        location: String,
        appName: String,
        bundleIdentifier: String
    ) -> MatchConfidence? {
        guard !isSystemOwned(entryName: entryName) else { return nil }
        guard !entryName.isEmpty, !bundleIdentifier.isEmpty else { return nil }

        let base = stripKnownSuffix(from: entryName)

        // Named for the bundle identifier itself, or a child namespace of it
        // (`com.brave.Browser.helper`). Effectively certain.
        if matchesIdentifier(base, bundleIdentifier) {
            return .confident
        }

        // Group containers carry a `group.` or team-identifier prefix in front of a
        // namespace that is usually an *ancestor* of the app's identifier —
        // `group.com.docker` for `com.docker.docker`. That relationship is real but it
        // is also shared: `group.com.microsoft` belongs to Word and Excel alike, so
        // removing it while uninstalling one of them would break the other.
        if let stripped = stripGroupPrefix(base) {
            if matchesIdentifier(stripped, bundleIdentifier) { return .confident }
            if bundleIdentifier.lowercased().hasPrefix(stripped.lowercased() + ".") { return .likely }
        }

        // The app's plain name, exactly, where that is the convention.
        if base.compare(appName, options: .caseInsensitive) == .orderedSame {
            return plainNameLocations.contains(location) ? .confident : .likely
        }

        // `Docker Desktop` for `Docker`. Anchored at the start and requiring a
        // separator, so `Bear` cannot reach `BeardedSpice` the way a substring would.
        if startsWithNameThenSeparator(base, appName) {
            return .likely
        }

        return nil
    }

    // MARK: - Rules

    private static func matchesIdentifier(_ candidate: String, _ bundleIdentifier: String) -> Bool {
        let candidate = candidate.lowercased()
        let identifier = bundleIdentifier.lowercased()
        return candidate == identifier || candidate.hasPrefix(identifier + ".")
    }

    private static func stripKnownSuffix(from name: String) -> String {
        for suffix in identifierSuffixes where name.lowercased().hasSuffix(suffix.lowercased()) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// Removes a leading `group.` or a ten-character team identifier (`U355UULQVV.`).
    private static func stripGroupPrefix(_ name: String) -> String? {
        if name.lowercased().hasPrefix("group.") {
            return String(name.dropFirst("group.".count))
        }
        let components = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if components.count == 2,
           components[0].count == 10,
           components[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            return String(components[1])
        }
        return nil
    }

    private static func startsWithNameThenSeparator(_ candidate: String, _ appName: String) -> Bool {
        guard appName.count >= 3 else {
            // Two-letter app names produce far too many prefix hits to be worth
            // offering at all.
            return false
        }
        let candidate = candidate.lowercased()
        let name = appName.lowercased()
        guard candidate.hasPrefix(name), candidate.count > name.count else { return false }

        let next = candidate[candidate.index(candidate.startIndex, offsetBy: name.count)]
        return next == " " || next == "-" || next == "_"
    }
}
