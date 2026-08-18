import Foundation

/// Lists user-removable applications.
///
/// Deliberately confined to `/Applications` and `~/Applications`. `/System/Applications`
/// holds the built-in OS apps, which are not meant to be removable and mostly cannot be
/// removed at all without disabling SIP.
///
/// Apple's own software is *listed but marked*, not silently dropped. Safari, Keynote,
/// Numbers, Pages and Xcode all ship into `/Applications` on a normal machine, and the
/// CLI's lister offers every one of them for removal. Hiding them would look like a bug
/// the first time somebody went looking for Safari; showing them as unremovable answers
/// the question instead.
public struct AppLister: Sendable {
    private let roots: [String]

    public init(roots: [String]) {
        self.roots = roots
    }

    public init(user: UserPaths = .current()) {
        self.init(roots: ["/Applications", user.inHome("Applications")])
    }

    /// - Throws: `CancellationError` when cancelled. Sizing a folder of large bundles
    ///   takes real time, so this stays interruptible throughout.
    public func listApps(sizer: DirectorySizer = DirectorySizer()) async throws -> [InstalledApp] {
        let bundlePaths = roots.flatMap { root in
            DirectoryListing.children(of: root).filter { $0.hasSuffix(".app") }
        }

        // Bundles are sized concurrently — one slow bundle (an IDE, a game) should not
        // hold up the other forty.
        let apps = try await withThrowingTaskGroup(of: InstalledApp?.self) { group in
            for path in bundlePaths {
                group.addTask {
                    try Task.checkCancellation()
                    return try Self.describe(path: path, sizer: sizer)
                }
            }

            var results: [InstalledApp] = []
            for try await app in group {
                if let app { results.append(app) }
            }
            return results
        }

        return apps.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func describe(path: String, sizer: DirectorySizer) throws -> InstalledApp? {
        // `Bundle` reads Info.plist natively. The CLI shells out to `plutil` for this;
        // there is no reason to spawn a process per app when Foundation already parses
        // the format.
        guard let bundle = Bundle(url: URL(fileURLWithPath: path)) else { return nil }
        guard let info = bundle.infoDictionary else {
            // No Info.plist means this is not a real app bundle — a stray directory
            // that happens to end in .app.
            return nil
        }

        let name = (path as NSString).lastPathComponent.replacingOccurrences(
            of: ".app", with: "", options: [.anchored, .backwards]
        )
        // An app with no identifier can still be listed, but only name matching will
        // work for its leftovers, which is exactly when matching is least reliable.
        let identifier = bundle.bundleIdentifier ?? ""

        return InstalledApp(
            path: path,
            name: name,
            bundleIdentifier: identifier,
            version: info["CFBundleShortVersionString"] as? String ?? "",
            sizeBytes: try sizer.size(of: path),
            lastUsed: lastUsedDate(of: path),
            isAppleSoftware: identifier.lowercased().hasPrefix("com.apple.")
        )
    }

    /// Last-opened where the filesystem records it, falling back to last-modified.
    /// Used only to sort and to label an app as unused for a while — never to decide
    /// anything on somebody's behalf.
    private static func lastUsedDate(of path: String) -> Date? {
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey]
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys)
        return values?.contentAccessDate ?? values?.contentModificationDate
    }
}
