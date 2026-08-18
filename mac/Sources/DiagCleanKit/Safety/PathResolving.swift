import Foundation

/// The narrow set of filesystem questions `PathGuard` needs to answer. Kept as a
/// protocol so guard behaviour can be exercised against synthetic answers in tests,
/// but the tests that matter run against `LivePathResolver` and real temp directories:
/// symlinks, case-insensitive volumes and permission errors are exactly the things a
/// hand-written fake gets subtly wrong, and those are the cases worth being sure about.
public protocol PathResolving: Sendable {
    /// `realpath(3)` for a path that exists, resolving every symlink in it. `nil` when
    /// the path does not exist or cannot be resolved.
    func realPath(of path: String) -> String?

    /// True when `path` itself is a symbolic link. Does not follow the link.
    func isSymbolicLink(at path: String) -> Bool
}

public struct LivePathResolver: PathResolving {
    public init() {}

    public func realPath(of path: String) -> String? {
        guard let resolved = Foundation.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public func isSymbolicLink(at path: String) -> Bool {
        var info = stat()
        // lstat, not stat: stat() follows the link and would report on the target.
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFLNK
    }
}
