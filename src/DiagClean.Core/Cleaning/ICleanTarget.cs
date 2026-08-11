using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// A single cleanable category (temp files, a browser's cache, etc). Implementations
/// only ever produce a <see cref="ScanResult"/> — actual deletion is centralized in
/// <see cref="Safety.DryRunEngine"/> so every target goes through the same guard checks.
/// </summary>
public interface ICleanTarget
{
    CleanCategory Category { get; }
    string DisplayName { get; }

    /// <summary>True if this target needs administrator rights to scan/clean (e.g. Windows Update cache).</summary>
    bool RequiresElevation { get; }

    /// <summary>The guard this target scanned with - callers must reuse it for the delete-time re-check.</summary>
    IPathGuard Guard { get; }

    ScanResult Scan();
}
