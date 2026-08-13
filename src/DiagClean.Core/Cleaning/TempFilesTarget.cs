using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Cleans the current user's temp directory and the machine-wide Windows\Temp directory.
/// Each top-level entry becomes its own CleanItem so the dry-run preview shows individual
/// files/folders rather than one opaque "temp" blob.
/// </summary>
public sealed class TempFilesTarget : CleanTargetBase, ICleanTarget
{
    private readonly IReadOnlyList<string> _roots;

    public TempFilesTarget(
        IFileSystem fileSystem, IPathGuard guard, IReadOnlyList<string> tempRoots, bool requiresElevation = true)
        : base(fileSystem, guard)
    {
        _roots = tempRoots;
        RequiresElevation = requiresElevation;
    }

    public CleanCategory Category => CleanCategory.TempFiles;
    public string DisplayName => "Temp Files";

    // Defaults to true: Windows' machine-wide Windows\Temp root needs admin rights to
    // clear fully. macOS's per-user temp dir (and /private/tmp for typical single-user
    // use) usually doesn't - the factory passes false there.
    public bool RequiresElevation { get; }

    public ScanResult Scan()
    {
        var candidates = _roots
            .SelectMany(root => SafeGetFiles(root).Concat(SafeGetDirectories(root)));

        return BuildScanResult(Category, candidates);
    }
}
