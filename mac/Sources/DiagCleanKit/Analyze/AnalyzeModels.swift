import Foundation

/// One entry in a directory listing, with its recursive size already measured.
public struct DiskEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let lastModified: Date?
    /// True when the size could not be fully measured because part of the tree was
    /// unreadable. Surfaced rather than hidden: a folder that reports 2 GB when it holds
    /// 40 GB of unreadable data is worse than one that admits it does not know.
    public let isPartial: Bool

    public init(
        path: String,
        name: String,
        sizeBytes: Int64,
        isDirectory: Bool,
        lastModified: Date?,
        isPartial: Bool = false
    ) {
        self.id = path
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.lastModified = lastModified
        self.isPartial = isPartial
    }
}

public struct DirectoryListing: Sendable {
    public let path: String
    public let entries: [DiskEntry]
    /// Directories that could not be opened at all. Shown as a count so the totals are
    /// visibly incomplete rather than quietly wrong.
    public let unreadableCount: Int

    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }

    public init(path: String, entries: [DiskEntry], unreadableCount: Int) {
        self.path = path
        self.entries = entries
        self.unreadableCount = unreadableCount
    }
}

/// How careful the confirmation should be about a particular removal.
public enum RemovalSensitivity: Sendable, Equatable {
    case normal
    /// Inside one of the directories where people keep work they cannot get back.
    /// Still removable — finding a forgotten 40 GB video in Movies is a real reason to
    /// use this tool — but the confirmation says plainly what it is.
    case personal(container: String)
}

public enum AnalyzeDenial: Equatable, Sendable {
    case volumeRoot
    case homeFolder
    case systemPath(String)
    case personalFolderItself(String)
    case essentialFolderItself(String)
    case credentials
    case auditTrail
    case applicationBundle(String)
    case symbolicLink
    case doesNotExist

    public var explanation: String {
        switch self {
        case .volumeRoot:
            return "This is the root of a volume. DiagClean will not remove an entire disk."
        case .homeFolder:
            return "This is your home folder. Removing it would take everything with it."
        case .systemPath(let path):
            return "\(path) belongs to macOS. Removing it would break the system."
        case .personalFolderItself(let name):
            return "This is your \(name) folder itself. You can remove things inside it, but not the folder."
        case .essentialFolderItself(let name):
            return "This is your \(name) folder. Everything your apps store lives in here. You can remove things inside it, but not the folder."
        case .credentials:
            return "This holds keys or credentials, which cannot be recovered by reinstalling anything."
        case .auditTrail:
            return "This is DiagClean's own record of what it has done on this machine."
        case .applicationBundle(let name):
            return "\(name) is an installed application. Use Uninstall instead, so its leftover files go too."
        case .symbolicLink:
            return "This is a symbolic link. DiagClean does not remove links."
        case .doesNotExist:
            return "This item is no longer there."
        }
    }
}

public enum AnalyzeDecision: Equatable, Sendable {
    case allowed(canonicalPath: String, sensitivity: RemovalSensitivity)
    case denied(AnalyzeDenial)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    public var denial: AnalyzeDenial? {
        if case .denied(let denial) = self { return denial }
        return nil
    }
}

public struct AnalyzeRemovalReport: Sendable {
    public let path: String
    public let name: String
    public let bytesFreed: Int64
    public let failure: String?

    public var succeeded: Bool { failure == nil }

    public init(path: String, name: String, bytesFreed: Int64, failure: String?) {
        self.path = path
        self.name = name
        self.bytesFreed = bytesFreed
        self.failure = failure
    }
}
