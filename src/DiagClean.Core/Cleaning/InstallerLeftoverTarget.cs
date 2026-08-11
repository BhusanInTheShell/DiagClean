using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Targets orphaned installer temp files only - *.msi/*.msp/*.tmp dropped in the temp
/// directories during install/uninstall runs. Deliberately does NOT touch
/// C:\Windows\Installer: that's the live MSI cache that Windows uses to service repair
/// and uninstall for currently-installed products, and identifying which entries in it
/// are truly orphaned requires cross-referencing the MSI product database - getting
/// that wrong breaks the ability to uninstall/repair software, which is far worse than
/// leaving a few extra megabytes behind. A safety-first tool leaves it alone.
/// </summary>
public sealed class InstallerLeftoverTarget : CleanTargetBase, ICleanTarget
{
    private static readonly string[] Patterns = ["*.msi", "*.msp", "*.tmp"];

    private readonly IReadOnlyList<string> _tempRoots;

    public InstallerLeftoverTarget(IFileSystem fileSystem, IPathGuard guard, IReadOnlyList<string> tempRoots)
        : base(fileSystem, guard)
    {
        _tempRoots = tempRoots;
    }

    public CleanCategory Category => CleanCategory.InstallerLeftovers;
    public string DisplayName => "Installer Leftovers";
    public bool RequiresElevation => true;

    public ScanResult Scan()
    {
        var candidates = _tempRoots.SelectMany(root => Patterns.SelectMany(pattern => SafeGetFiles(root, pattern)));
        return BuildScanResult(Category, candidates);
    }
}
