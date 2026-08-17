import Foundation

/// A real directory under a real temp folder, with real symlinks and real permissions.
///
/// The safety tests deliberately do not use a fake filesystem. Every hole this guard
/// exists to close — case-insensitive volumes, symlinks, paths that resolve somewhere
/// other than where they appear to — is a place where a hand-written fake would agree
/// with the code under test and both would be wrong together.
final class TempWorkspace {
    let root: String

    init(function: String = #function) throws {
        let name = "diagclean-tests-\(UUID().uuidString)"
        let base = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        // realpath(3), not `resolvingSymlinksInPath`: macOS temp directories live under
        // /var/folders, and /var is a symlink to /private/var. Foundation's method
        // helpfully strips the /private prefix back off again, which is the opposite of
        // what these tests need — they compare against the paths the guard canonicalises
        // to, and those are genuinely /private/var.
        self.root = Self.realPath(of: base) ?? base
    }

    private static func realPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    func path(_ components: String...) -> String {
        components.reduce(root) { ($0 as NSString).appendingPathComponent($1) }
    }

    @discardableResult
    func makeDirectory(_ components: String...) throws -> String {
        let path = components.reduce(root) { ($0 as NSString).appendingPathComponent($1) }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Creates a file of `bytes` length, creating parent directories as needed.
    @discardableResult
    func makeFile(_ relativePath: String, bytes: Int = 1024, modified: Date? = nil) throws -> String {
        let path = (root as NSString).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: URL(fileURLWithPath: path))
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
        }
        return path
    }

    @discardableResult
    func makeSymlink(_ relativePath: String, to destination: String) throws -> String {
        let path = (root as NSString).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
        return path
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func setModificationDate(_ date: Date, of path: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }
}
