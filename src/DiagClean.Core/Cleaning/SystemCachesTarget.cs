using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Sweeps the top-level entries of a general per-app cache root (macOS's
/// ~/Library/Caches - Apple's own convention is that anything here is safe to delete
/// and apps must regenerate it on demand, the same guarantee Windows gives for Temp).
/// This is the macOS analog to "common bloat and leftover files" - Windows gets more
/// specific targets (Windows Update, installer leftovers) because those are meaningful
/// Windows-specific concepts; macOS doesn't have an equivalent, so one general sweep
/// covers the same intent. Entries already handled by BrowserCacheTarget are excluded
/// here to avoid reporting (and offering to delete) the same bytes twice.
/// </summary>
public sealed class SystemCachesTarget : CleanTargetBase, ICleanTarget
{
    private readonly string _cachesRoot;
    private readonly HashSet<string> _excludedTopLevelNames;

    public SystemCachesTarget(
        IFileSystem fileSystem, IPathGuard guard, string cachesRoot, IEnumerable<string>? excludedTopLevelNames = null)
        : base(fileSystem, guard)
    {
        _cachesRoot = cachesRoot;
        _excludedTopLevelNames = new HashSet<string>(excludedTopLevelNames ?? [], StringComparer.OrdinalIgnoreCase);
    }

    public CleanCategory Category => CleanCategory.SystemCaches;
    public string DisplayName => "System Caches";
    public bool RequiresElevation => false;

    public ScanResult Scan()
    {
        var candidates = SafeGetDirectories(_cachesRoot)
            .Concat(SafeGetFiles(_cachesRoot))
            .Where(p => !_excludedTopLevelNames.Contains(FileSystem.Path.GetFileName(p)));

        return BuildScanResult(Category, candidates);
    }
}
