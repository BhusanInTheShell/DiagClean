import Foundation

/// The three things Clean knows how to reclaim. Deliberately few: each one is a
/// category a technician can explain to the person whose machine it is, and each holds
/// only data the system regenerates on demand. Anything that needed a paragraph of
/// caveats to justify does not belong here.
public enum CleanCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case temporaryFiles
    case browserCaches
    case applicationCaches

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .temporaryFiles: return "Temporary Files"
        case .browserCaches: return "Browser Caches"
        case .applicationCaches: return "Application Caches"
        }
    }

    /// Shown under the title in the review list. This is the sentence a technician
    /// repeats to the machine's owner, so it says what comes back and what doesn't.
    public var summary: String {
        switch self {
        case .temporaryFiles:
            return "Scratch files left behind by apps, untouched for at least a day. Regenerated as needed."
        case .browserCaches:
            return "Cached pages, images and shader data. Browsers rebuild these; history and logins are untouched."
        case .applicationCaches:
            return "Per-app caches in your Library. Apps rebuild these on next launch; the first launch may be slower."
        }
    }
}

/// One thing that would be removed. Always a real path with a real measured size —
/// nothing in the preview is an estimate or a placeholder, because the preview is the
/// whole basis on which someone says yes.
public struct CleanItem: Identifiable, Sendable, Hashable, Codable {
    /// The canonical path, as resolved by the guard that admitted it.
    public let id: String
    public let path: String
    public let category: CleanCategory
    /// Which app or area this belongs to — "Brave Browser", "Spotlight". Used to group
    /// the review list into rows a person recognises instead of a wall of paths.
    public let ownerLabel: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let lastModified: Date?

    public init(
        path: String,
        category: CleanCategory,
        ownerLabel: String,
        sizeBytes: Int64,
        isDirectory: Bool,
        lastModified: Date?
    ) {
        self.id = path
        self.path = path
        self.category = category
        self.ownerLabel = ownerLabel
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.lastModified = lastModified
    }
}

/// A path the scan deliberately declined to offer. Surfaced in the UI rather than
/// swallowed: "why isn't my 4 GB cache in the list" should always have a visible answer.
public struct SkippedPath: Sendable, Hashable, Codable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct CategoryScan: Identifiable, Sendable, Codable {
    public let category: CleanCategory
    public let items: [CleanItem]
    public let skipped: [SkippedPath]

    public var id: CleanCategory { category }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var itemCount: Int { items.count }

    public init(category: CleanCategory, items: [CleanItem], skipped: [SkippedPath]) {
        self.category = category
        self.items = items
        self.skipped = skipped
    }
}

/// The complete result of a scan. Nothing has been touched at this point and nothing
/// will be until a `CleanPlan` built from it is handed to the executor.
public struct CleanScan: Sendable, Codable {
    public let categories: [CategoryScan]
    public let startedAt: Date
    public let finishedAt: Date

    public var totalBytes: Int64 { categories.reduce(0) { $0 + $1.totalBytes } }
    public var itemCount: Int { categories.reduce(0) { $0 + $1.itemCount } }
    public var allItems: [CleanItem] { categories.flatMap(\.items) }

    public init(categories: [CategoryScan], startedAt: Date, finishedAt: Date) {
        self.categories = categories
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

/// Exactly what the technician confirmed, and the only thing the executor will act on.
/// Constructed from a scan plus an explicit selection — there is no initialiser that
/// turns a scan straight into a plan, so "clean everything" is always something a
/// person chose rather than something that happened by default.
public struct CleanPlan: Sendable {
    public let items: [CleanItem]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var itemCount: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    public init(items: [CleanItem]) {
        // Deepest paths first. If a plan ever contains both a directory and something
        // inside it, removing the child first keeps the reported byte totals honest
        // instead of counting the same bytes twice.
        self.items = items.sorted { $0.path.count > $1.path.count }
    }
}

public struct CleanFailure: Sendable, Hashable, Codable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct CleanReport: Sendable, Codable {
    public let bytesFreed: Int64
    public let itemsRemoved: Int
    public let failures: [CleanFailure]
    /// True when the technician cancelled partway. The items already removed are still
    /// counted — a cancelled run is a partial run, not a no-op, and pretending
    /// otherwise would be the single most misleading thing this screen could say.
    public let wasCancelled: Bool
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        bytesFreed: Int64,
        itemsRemoved: Int,
        failures: [CleanFailure],
        wasCancelled: Bool,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.bytesFreed = bytesFreed
        self.itemsRemoved = itemsRemoved
        self.failures = failures
        self.wasCancelled = wasCancelled
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
