import Foundation

/// Why a path was refused. Every denial carries enough detail to show a technician
/// exactly what the guard objected to — a silent "skipped 4 items" teaches nobody
/// anything and looks like a bug the first time it hides something legitimate.
public enum GuardDenial: Equatable, Sendable {
    case notAbsolute
    case filesystemRoot
    case symbolicLink
    case unresolvable(reason: String)
    case isAllowedRootItself(root: String)
    case outsideAllowedRoots
    case protectedPath(match: String)

    public var explanation: String {
        switch self {
        case .notAbsolute:
            return "path is not absolute"
        case .filesystemRoot:
            return "path is the filesystem root"
        case .symbolicLink:
            return "path is a symbolic link"
        case .unresolvable(let reason):
            return "path could not be resolved: \(reason)"
        case .isAllowedRootItself(let root):
            return "path is the root \(root) itself, not something inside it"
        case .outsideAllowedRoots:
            return "path is outside the allowed roots for this operation"
        case .protectedPath(let match):
            return "path is protected (\(match))"
        }
    }
}

public enum GuardDecision: Equatable, Sendable {
    case allowed(canonicalPath: String)
    case denied(GuardDenial)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    public var denial: GuardDenial? {
        if case .denied(let denial) = self { return denial }
        return nil
    }
}

/// Enforces the two independent checks that must both pass before DiagClean touches
/// anything on disk, inherited from the CLI's safety model:
///
///   1. The path must be a *strict* descendant of one of the caller's declared allowed
///      roots — defence in depth against a target scanning somewhere it shouldn't.
///   2. It must not fall under a protected path, built-in or user-configured.
///
/// Neither list is meant to be sufficient on its own, and neither can be waived.
///
/// Three deliberate differences from the CLI's `PathGuard`, each covering a hole that
/// only exists on macOS:
///
///   * **Protected matching is case-insensitive.** The CLI compares ordinally on
///     non-Windows, but the default macOS root volume is case-insensitive APFS —
///     `/Users/me/documents/tax` and `/Users/me/Documents/tax` are the same file, and
///     an ordinal comparison only recognises one of them as protected.
///   * **Strict descendants only.** The CLI's check passes when the candidate *equals*
///     an allowed root, so a bug that produced the bare root path would be permitted to
///     delete the whole root. Nothing here may name a root itself.
///   * **Symlinks are refused outright**, and the parent chain is canonicalised through
///     `realpath` before the root check, so neither the item nor any ancestor can be a
///     link out of the allowed root into real data.
public struct PathGuard: Sendable {
    private let allowedRoots: [String]
    private let protectedPaths: [String]
    private let resolver: PathResolving

    /// - Parameters:
    ///   - allowedRoots: the only places this guard will ever permit. Canonicalised on
    ///     construction so a root reached through a symlink (`/tmp` → `/private/tmp`)
    ///     compares equal to the same root reached directly.
    ///   - protectedPaths: vetoes applied on top, checked before the roots.
    public init(
        allowedRoots: [String],
        protectedPaths: [String],
        resolver: PathResolving = LivePathResolver()
    ) {
        self.resolver = resolver
        self.allowedRoots = allowedRoots.map { Self.canonicalize($0, using: resolver) }
        // Protected paths are kept in both canonical and lexical form. A protected
        // directory that doesn't exist yet still can't be resolved by realpath, and
        // "doesn't exist right now" must not mean "not protected".
        self.protectedPaths = protectedPaths
            .flatMap { [Self.standardize($0), Self.canonicalize($0, using: resolver)] }
            .uniqued()
    }

    public func decide(_ path: String) -> GuardDecision {
        // Checked on the input, before standardisation: `URL(fileURLWithPath:)`
        // resolves a relative path against the process's current working directory, so
        // testing afterwards would find every path absolute and quietly accept one that
        // means something entirely different from what the caller intended.
        guard path.hasPrefix("/") else {
            return .denied(.notAbsolute)
        }

        let standardized = Self.standardize(path)
        guard standardized != "/" else {
            return .denied(.filesystemRoot)
        }
        guard !resolver.isSymbolicLink(at: standardized) else {
            return .denied(.symbolicLink)
        }

        // Resolve the *parent* rather than the path itself: realpath on the path would
        // follow a final symlink, and we want to judge the item where it sits, not
        // wherever it points. The symlink check above has already ruled that case out,
        // but resolving the parent is what catches an ancestor link.
        let parent = (standardized as NSString).deletingLastPathComponent
        let leaf = (standardized as NSString).lastPathComponent
        guard let resolvedParent = resolver.realPath(of: parent) else {
            return .denied(.unresolvable(reason: "parent directory \(parent) does not resolve"))
        }
        let canonical = (resolvedParent as NSString).appendingPathComponent(leaf)

        // Protected wins over allowed, always, and is checked against both the path we
        // were handed and the path it really is.
        for candidate in [standardized, canonical] {
            if let match = protectedPaths.first(where: { Self.isSameOrDescendant(candidate, of: $0) }) {
                return .denied(.protectedPath(match: match))
            }
        }

        if let root = allowedRoots.first(where: { Self.pathsEqual(canonical, $0) }) {
            return .denied(.isAllowedRootItself(root: root))
        }
        guard allowedRoots.contains(where: { Self.isStrictDescendant(canonical, of: $0) }) else {
            return .denied(.outsideAllowedRoots)
        }

        return .allowed(canonicalPath: canonical)
    }

    public func isAllowed(_ path: String) -> Bool {
        decide(path).isAllowed
    }

    // MARK: - Path arithmetic

    /// Lexical cleanup only — removes `.`, `..` and duplicate separators without
    /// touching symlinks. Deliberately not `NSString.standardizingPath`, which also
    /// resolves symlinks for some prefixes and expands `~`; canonicalisation here needs
    /// to be one explicit, predictable step rather than two implicit ones.
    static func standardize(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return trimTrailingSlash(url.path)
    }

    static func canonicalize(_ path: String, using resolver: PathResolving) -> String {
        let standardized = standardize(path)
        guard let resolved = resolver.realPath(of: standardized) else { return standardized }
        return trimTrailingSlash(resolved)
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    /// Case- and Unicode-normalisation-insensitive. APFS preserves the case and
    /// composition you give it but matches without regard to either, so two strings that
    /// differ only that way name the same file and must be treated as the same path.
    private static func fold(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        fold(lhs) == fold(rhs)
    }

    static func isStrictDescendant(_ candidate: String, of root: String) -> Bool {
        let candidate = fold(candidate)
        let root = fold(root)
        guard candidate != root else { return false }
        return candidate.hasPrefix(root == "/" ? "/" : root + "/")
    }

    static func isSameOrDescendant(_ candidate: String, of root: String) -> Bool {
        pathsEqual(candidate, root) || isStrictDescendant(candidate, of: root)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
