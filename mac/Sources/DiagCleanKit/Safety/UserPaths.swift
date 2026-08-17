import Foundation

/// Where this user's things live. Injectable so tests can point an entire scan at a
/// synthetic home directory under a temp folder and exercise the real targets, real
/// guard and real executor against it rather than mocking them out.
public struct UserPaths: Sendable {
    public let home: String

    public init(home: String) {
        self.home = PathGuard.standardize(home)
    }

    /// The real invoking user's home. `NSHomeDirectory()` inside a sandboxed app points
    /// at the container, not the actual home, so this reads the passwd entry instead —
    /// DiagClean needs to see the genuine `~/Library`, and being wrong about that would
    /// silently produce an empty, reassuring, useless scan.
    public static func current() -> UserPaths {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return UserPaths(home: String(cString: dir))
        }
        return UserPaths(home: NSHomeDirectory())
    }

    public func inHome(_ components: String...) -> String {
        components.reduce(home) { ($0 as NSString).appendingPathComponent($1) }
    }

    public var library: String { inHome("Library") }
    public var caches: String { inHome("Library", "Caches") }
    public var applicationSupport: String { inHome("Library", "Application Support") }
    public var logs: String { inHome("Library", "Logs") }
    public var trash: String { inHome(".Trash") }

    /// DiagClean's own state, deliberately the same directory the CLI writes to so a
    /// machine has one audit trail regardless of which tool did the work.
    public var appSupportDirectory: String { inHome("Library", "Application Support", "DiagClean") }
    public var logsDirectory: String { (appSupportDirectory as NSString).appendingPathComponent("logs") }
}
