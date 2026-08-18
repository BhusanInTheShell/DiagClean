import Foundation

/// One scannable area of the disk. A target knows how to find its own candidates and
/// carries the guard those candidates must satisfy — the guard travels with the target
/// so the executor can re-check every path against the same rules that admitted it,
/// rather than against some looser ambient policy.
public protocol CleanTarget: Sendable {
    var category: CleanCategory { get }
    var pathGuard: PathGuard { get }
    /// Candidate paths, unmeasured and unchecked. `CleanScanner` applies the guard and
    /// measures sizes; a target's only job is to say where to look.
    func candidates() -> [Candidate]
}

/// A path a target believes is worth offering, with the label to show for it.
public struct Candidate: Sendable, Hashable {
    public let path: String
    public let ownerLabel: String

    public init(path: String, ownerLabel: String) {
        self.path = path
        self.ownerLabel = ownerLabel
    }
}

// MARK: - Shared enumeration helpers

/// Small filesystem helpers shared by every scanner. Named for what it does rather than
/// what it returns, so `DirectoryListing` stays free for the model that actually is one.
enum FileSystemListing {
    /// Immediate children of `path`, hidden entries included, symlinks excluded.
    /// Failures are silence rather than errors: an unreadable directory should cost the
    /// scan that one directory, never the whole report.
    static func children(of path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return [] }

        return contents.compactMap { child in
            let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true { return nil }
            return child.path
        }
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func modificationDate(of path: String) -> Date? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
