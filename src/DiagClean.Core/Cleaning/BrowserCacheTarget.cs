using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Clears cache directories for Chromium-based browsers (Chrome, Edge) and Firefox.
/// Each browser recreates its cache folder on next launch, so deleting the whole
/// directory (rather than walking its contents) is both simpler and safe.
/// </summary>
public sealed class BrowserCacheTarget : CleanTargetBase, ICleanTarget
{
    private readonly string _localAppData;
    private readonly string _appData;

    public BrowserCacheTarget(IFileSystem fileSystem, IPathGuard guard, string localAppData, string appData)
        : base(fileSystem, guard)
    {
        _localAppData = localAppData;
        _appData = appData;
    }

    public CleanCategory Category => CleanCategory.BrowserCache;
    public string DisplayName => "Browser Cache";
    public bool RequiresElevation => false;

    public ScanResult Scan()
    {
        var candidates = new List<string>();
        candidates.AddRange(FindChromiumCaches(FileSystem.Path.Combine(_localAppData, "Google", "Chrome", "User Data")));
        candidates.AddRange(FindChromiumCaches(FileSystem.Path.Combine(_localAppData, "Microsoft", "Edge", "User Data")));
        candidates.AddRange(FindFirefoxCaches());

        return BuildScanResult(Category, candidates);
    }

    private IEnumerable<string> FindChromiumCaches(string userDataRoot)
    {
        // Chromium profiles are "Default" plus "Profile 1", "Profile 2", ... each with its own Cache folder.
        foreach (var profileDir in SafeGetDirectories(userDataRoot))
        {
            var name = FileSystem.Path.GetFileName(profileDir);
            if (!string.Equals(name, "Default", StringComparison.OrdinalIgnoreCase) &&
                !name.StartsWith("Profile ", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var cacheDir = FileSystem.Path.Combine(profileDir, "Cache");
            if (FileSystem.Directory.Exists(cacheDir))
            {
                yield return cacheDir;
            }

            var codeCacheDir = FileSystem.Path.Combine(profileDir, "Code Cache");
            if (FileSystem.Directory.Exists(codeCacheDir))
            {
                yield return codeCacheDir;
            }
        }
    }

    private IEnumerable<string> FindFirefoxCaches()
    {
        // Firefox cache (cache2) lives under LocalAppData even though the rest of the
        // profile lives under Roaming AppData; profile folder names are random.
        var profilesRoot = FileSystem.Path.Combine(_localAppData, "Mozilla", "Firefox", "Profiles");
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
