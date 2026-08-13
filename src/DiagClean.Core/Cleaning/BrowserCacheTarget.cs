using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Clears cache directories for Chromium-based browsers (Chrome, Edge) and Firefox,
/// plus any number of standalone single-directory browser caches (e.g. Safari).
/// Callers supply the actual root paths since they differ structurally by OS - Windows
/// nests everything under a "User Data" folder inside LocalAppData; macOS puts profile
/// folders directly under Application Support with no such wrapper, and Firefox splits
/// profile data (Application Support) from disk cache (~/Library/Caches) there in a way
/// Windows doesn't. Each browser recreates its cache folder on next launch, so deleting
/// the whole folder (rather than walking its contents) is both simpler and safe.
/// </summary>
public sealed class BrowserCacheTarget : CleanTargetBase, ICleanTarget
{
    // Chromium's actual cache-bearing subfolder names have varied across versions and
    // platforms (confirmed live on macOS: GPUCache/DawnWebGPUCache/DawnGraphiteCache
    // exist even when the classic "Cache" folder is momentarily empty/absent) - checking
    // this whole list is more robust than assuming just "Cache" and "Code Cache".
    private static readonly string[] ChromiumCacheSubfolders =
        ["Cache", "Code Cache", "GPUCache", "DawnWebGPUCache", "DawnGraphiteCache"];

    private readonly IReadOnlyList<string> _chromiumProfileRoots;
    private readonly IReadOnlyList<string> _firefoxProfileParents;
    private readonly IReadOnlyList<string> _standaloneCacheDirs;

    public BrowserCacheTarget(
        IFileSystem fileSystem,
        IPathGuard guard,
        IReadOnlyList<string> chromiumProfileRoots,
        IReadOnlyList<string> firefoxProfileParents,
        IReadOnlyList<string>? standaloneCacheDirs = null)
        : base(fileSystem, guard)
    {
        _chromiumProfileRoots = chromiumProfileRoots;
        _firefoxProfileParents = firefoxProfileParents;
        _standaloneCacheDirs = standaloneCacheDirs ?? [];
    }

    public CleanCategory Category => CleanCategory.BrowserCache;
    public string DisplayName => "Browser Cache";
    public bool RequiresElevation => false;

    public ScanResult Scan()
    {
        var candidates = new List<string>();

        foreach (var root in _chromiumProfileRoots)
        {
            candidates.AddRange(FindChromiumCaches(root));
        }

        foreach (var root in _firefoxProfileParents)
        {
            candidates.AddRange(FindFirefoxCaches(root));
        }

        foreach (var dir in _standaloneCacheDirs)
        {
            if (FileSystem.Directory.Exists(dir))
            {
                candidates.Add(dir);
            }
        }

        return BuildScanResult(Category, candidates.Distinct());
    }

    private IEnumerable<string> FindChromiumCaches(string profileRoot)
    {
        // Chromium profiles are "Default" plus "Profile 1", "Profile 2", ...
        foreach (var profileDir in SafeGetDirectories(profileRoot))
        {
            var name = FileSystem.Path.GetFileName(profileDir);
            if (!string.Equals(name, "Default", StringComparison.OrdinalIgnoreCase) &&
                !name.StartsWith("Profile ", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            foreach (var sub in ChromiumCacheSubfolders)
            {
                var cacheDir = FileSystem.Path.Combine(profileDir, sub);
                if (FileSystem.Directory.Exists(cacheDir))
                {
                    yield return cacheDir;
                }
            }
        }
    }

    private IEnumerable<string> FindFirefoxCaches(string profilesRoot)
    {
        // Firefox profile folder names are random per-install; "cache2" is the fixed
        // subfolder name for the disk cache within each one.
        foreach (var profileDir in SafeGetDirectories(profilesRoot))
        {
            var cacheDir = FileSystem.Path.Combine(profileDir, "cache2");
            if (FileSystem.Directory.Exists(cacheDir))
            {
                yield return cacheDir;
            }
        }
    }
}
