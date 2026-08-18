import Foundation

/// Browser caches for the Chromium family, Firefox and Safari.
///
/// On macOS a Chromium browser splits its caches across two trees — the HTTP and code
/// caches under `~/Library/Caches/<vendor>/<browser>`, and the GPU and shader caches
/// under `~/Library/Application Support/<vendor>/<browser>` — so both are covered. The
/// allowed roots are the individual browser directories, never `~/Library/Caches` or
/// `~/Library/Application Support` wholesale: this target has no business anywhere
/// except inside a browser it recognises, and the guard should say so.
///
/// Only cache directories with fixed, well-known names are offered. Cookies, history,
/// saved passwords, extensions and open tabs all live beside them under the same
/// profile and are never candidates — "it logged everyone out of everything" is the
/// fastest way for a cleanup tool to lose a technician's trust permanently.
public struct BrowserCachesTarget: CleanTarget {
    public let category = CleanCategory.browserCaches
    public let pathGuard: PathGuard

    private let browsers: [ChromiumBrowser]
    private let cachesRoot: String
    private let applicationSupportRoot: String

    /// Cache directories that sit directly in a Chromium browser's data directory,
    /// outside any profile.
    private static let browserLevelCacheNames = [
        "ShaderCache", "GrShaderCache", "GraphiteDawnCache", "GPUPersistentCache",
    ]

    /// Cache directories that sit inside each Chromium profile. The Dawn and GPU
    /// entries were confirmed present on a live machine even when the classic `Cache`
    /// directory was absent, so checking the whole list beats assuming just `Cache`.
    private static let profileLevelCacheNames = [
        "Cache", "Code Cache", "GPUCache", "DawnWebGPUCache", "DawnGraphiteCache",
    ]

    public struct ChromiumBrowser: Sendable, Hashable {
        public let label: String
        /// Path relative to both `~/Library/Caches` and `~/Library/Application Support`.
        /// Chromium builds use the same layout under each.
        public let relativePath: String

        public init(label: String, relativePath: String) {
            self.label = label
            self.relativePath = relativePath
        }
    }

    public static let knownChromiumBrowsers: [ChromiumBrowser] = [
        .init(label: "Google Chrome", relativePath: "Google/Chrome"),
        .init(label: "Google Chrome Canary", relativePath: "Google/Chrome Canary"),
        // Brave is the largest cache on plenty of real machines and the CLI misses it
        // entirely; the whole point of a table rather than a hardcoded pair is that
        // adding the next one is a single line.
        .init(label: "Brave Browser", relativePath: "BraveSoftware/Brave-Browser"),
        .init(label: "Microsoft Edge", relativePath: "Microsoft Edge"),
        .init(label: "Vivaldi", relativePath: "Vivaldi"),
        .init(label: "Opera", relativePath: "com.operasoftware.Opera"),
        .init(label: "Arc", relativePath: "Arc"),
        .init(label: "Chromium", relativePath: "Chromium"),
    ]

    private let firefoxLabel = "Firefox"
    private let safariLabel = "Safari"

    public init(
        user: UserPaths,
        protectedPaths: [String],
        browsers: [ChromiumBrowser] = BrowserCachesTarget.knownChromiumBrowsers,
        resolver: PathResolving = LivePathResolver()
    ) {
        self.browsers = browsers
        self.cachesRoot = user.caches
        self.applicationSupportRoot = user.applicationSupport

        var roots: [String] = []
        for browser in browsers {
            roots.append((user.caches as NSString).appendingPathComponent(browser.relativePath))
            roots.append((user.applicationSupport as NSString).appendingPathComponent(browser.relativePath))
        }
        roots.append((user.caches as NSString).appendingPathComponent("Firefox"))
        // Safari's cache directory is the allowed root and its children are the
        // candidates, rather than the directory itself being the candidate under a
        // root of `~/Library/Caches`. Same bytes freed, far narrower blast radius.
        roots.append((user.caches as NSString).appendingPathComponent("com.apple.Safari"))

        self.pathGuard = PathGuard(
            allowedRoots: roots,
            protectedPaths: protectedPaths,
            resolver: resolver
        )
    }

    public func candidates() -> [Candidate] {
        var results: [Candidate] = []
        for browser in browsers {
            results.append(contentsOf: chromiumCandidates(for: browser))
        }
        results.append(contentsOf: firefoxCandidates())
        results.append(contentsOf: safariCandidates())
        return results
    }

    private func chromiumCandidates(for browser: ChromiumBrowser) -> [Candidate] {
        var results: [Candidate] = []

        for root in [
            (cachesRoot as NSString).appendingPathComponent(browser.relativePath),
            (applicationSupportRoot as NSString).appendingPathComponent(browser.relativePath),
        ] {
            guard FileSystemListing.exists(root) else { continue }

            for name in Self.browserLevelCacheNames {
                let path = (root as NSString).appendingPathComponent(name)
                if FileSystemListing.exists(path) {
                    results.append(Candidate(path: path, ownerLabel: browser.label))
                }
            }

            for profile in FileSystemListing.children(of: root) where Self.isProfileDirectory(profile) {
                for name in Self.profileLevelCacheNames {
                    let path = (profile as NSString).appendingPathComponent(name)
                    if FileSystemListing.exists(path) {
                        results.append(Candidate(path: path, ownerLabel: browser.label))
                    }
                }
            }
        }

        return results
    }

    /// Chromium names profiles `Default`, `Profile 1`, `Profile 2`, plus the `Guest
    /// Profile` and `System Profile` pseudo-profiles.
    private static func isProfileDirectory(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name == "Default"
            || name == "Guest Profile"
            || name == "System Profile"
            || name.hasPrefix("Profile ")
    }

    private func firefoxCandidates() -> [Candidate] {
        // Firefox profile directory names are randomised per install; `cache2` is the
        // fixed name of the disk cache inside each one.
        let profilesRoot = (cachesRoot as NSString).appendingPathComponent("Firefox/Profiles")
        guard FileSystemListing.exists(profilesRoot) else { return [] }

        return FileSystemListing.children(of: profilesRoot).compactMap { profile in
            let cache = (profile as NSString).appendingPathComponent("cache2")
            guard FileSystemListing.exists(cache) else { return nil }
            return Candidate(path: cache, ownerLabel: firefoxLabel)
        }
    }

    private func safariCandidates() -> [Candidate] {
        let root = (cachesRoot as NSString).appendingPathComponent("com.apple.Safari")
        guard FileSystemListing.exists(root) else { return [] }
        return FileSystemListing.children(of: root).map { Candidate(path: $0, ownerLabel: safariLabel) }
    }
}
