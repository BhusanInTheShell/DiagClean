import Foundation

/// An app discoverable in `/Applications` or `~/Applications`.
public struct InstalledApp: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    /// The bundle path. Moving this to the Trash is what "uninstalling" means on macOS.
    public let path: String
    public let name: String
    /// The bundle identifier — `com.brave.Browser`. This is what leftover matching keys
    /// off, because it is the only name an app uses consistently for its own files.
    public let bundleIdentifier: String
    public let version: String
    public let sizeBytes: Int64
    public let lastUsed: Date?
    /// Apple's own software, which this tool refuses to remove. Kept as a property
    /// rather than filtered out of the list so the UI can show *why* it can't be picked;
    /// silently omitting Safari would just look like a bug.
    public let isAppleSoftware: Bool

    public init(
        path: String,
        name: String,
        bundleIdentifier: String,
        version: String,
        sizeBytes: Int64,
        lastUsed: Date?,
        isAppleSoftware: Bool
    ) {
        self.id = path
        self.path = path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.sizeBytes = sizeBytes
        self.lastUsed = lastUsed
        self.isAppleSoftware = isAppleSoftware
    }
}

/// How sure the matcher is that a file belongs to the app being removed.
///
/// The distinction drives what is ticked by default. Confident matches are named after
/// the app's own bundle identifier and are effectively certain; likely matches are
/// name-based, are occasionally wrong, and are therefore shown unticked so removing one
/// is always somebody's decision rather than a default.
public enum MatchConfidence: String, Sendable, Codable, CaseIterable {
    case confident
    case likely

    public var isSelectedByDefault: Bool { self == .confident }

    public var label: String {
        switch self {
        case .confident: return "Matches bundle ID"
        case .likely: return "Matches name"
        }
    }
}

public struct LeftoverItem: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let path: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let confidence: MatchConfidence
    /// Which Library directory this came from — "Preferences", "Containers". Gives the
    /// review list a column that means something without reading the full path.
    public let location: String

    public init(
        path: String,
        sizeBytes: Int64,
        isDirectory: Bool,
        confidence: MatchConfidence,
        location: String
    ) {
        self.id = path
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.confidence = confidence
        self.location = location
    }
}

public struct LeftoverScan: Sendable, Codable {
    public let app: InstalledApp
    public let items: [LeftoverItem]
    public let skipped: [SkippedPath]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    /// The app bundle plus everything found beside it.
    public var totalWithAppBytes: Int64 { totalBytes + app.sizeBytes }

    public init(app: InstalledApp, items: [LeftoverItem], skipped: [SkippedPath]) {
        self.app = app
        self.items = items
        self.skipped = skipped
    }
}

/// Exactly what was confirmed. Built from a scan plus an explicit selection; there is no
/// initialiser that turns a scan straight into a plan.
public struct UninstallPlan: Sendable {
    public let app: InstalledApp
    public let includeApp: Bool
    public let leftovers: [LeftoverItem]

    public var totalBytes: Int64 {
        leftovers.reduce(includeApp ? app.sizeBytes : 0) { $0 + $1.sizeBytes }
    }
    public var itemCount: Int { leftovers.count + (includeApp ? 1 : 0) }
    public var isEmpty: Bool { itemCount == 0 }

    public init(app: InstalledApp, includeApp: Bool, leftovers: [LeftoverItem]) {
        self.app = app
        self.includeApp = includeApp
        // Deepest first, so a nested pair never has its bytes counted twice.
        self.leftovers = leftovers.sorted { $0.path.count > $1.path.count }
    }
}

public struct UninstallReport: Sendable, Codable {
    public let appName: String
    public let appRemoved: Bool
    public let leftoversRemoved: Int
    public let bytesFreed: Int64
    public let failures: [CleanFailure]
    public let wasCancelled: Bool
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        appName: String,
        appRemoved: Bool,
        leftoversRemoved: Int,
        bytesFreed: Int64,
        failures: [CleanFailure],
        wasCancelled: Bool,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.appName = appName
        self.appRemoved = appRemoved
        self.leftoversRemoved = leftoversRemoved
        self.bytesFreed = bytesFreed
        self.failures = failures
        self.wasCancelled = wasCancelled
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
