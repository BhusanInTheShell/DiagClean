using System.IO.Abstractions;
using System.Runtime.Versioning;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Uninstall.Mac;

/// <summary>
/// Removes an app bundle and its leftover files by moving them to ~/.Trash rather than
/// deleting them outright - recoverable if the wrong app gets picked, unlike Clean's
/// permanent deletion of regenerable cache/temp junk. This is a deliberately higher
/// safety bar than Clean: removing someone's actual installed software is a much
/// higher-stakes mistake than deleting a cache folder that regenerates on next launch.
///
/// Leftover matching is name/bundle-identifier substring matching against a fixed set of
/// known per-user Library locations - the same kind of best-effort heuristic already
/// used for SMART status matching in DiskHealthCollector. Deliberately scoped to the
/// user's own Library only (no /Library/LaunchAgents, /Library/Application Support,
/// etc.) - those are root-owned and shared across all users, and the vast majority of a
/// typical app's real footprint lives under the user's own Library anyway.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacAppUninstaller : IAppUninstaller
{
    private readonly IFileSystem _fileSystem;
    private readonly IReadOnlyList<string> _leftoverRoots;

    public MacAppUninstaller(IFileSystem fileSystem, IPathGuard guard, IReadOnlyList<string> leftoverRoots)
    {
        _fileSystem = fileSystem;
        Guard = guard;
        _leftoverRoots = leftoverRoots;
    }

    public UninstallMethod Method => UninstallMethod.DirectRemoval;
    public IPathGuard Guard { get; }

    public AppLeftoverScanResult ScanLeftovers(InstalledApp app) =>
        LeftoverScanner.Scan(_fileSystem, Guard, app, _leftoverRoots, [app.Identifier, app.Name]);

    public UninstallOutcome RemoveDirectly(InstalledApp app, IReadOnlyList<AppLeftoverItem> leftoverItems)
    {
        var failures = new List<CleanFailure>();
        long bytesFreed = 0;
        var appItemsRemoved = 0;
        var leftoverItemsRemoved = 0;

        var appRemoved = TryTrash(app.InstallPath, app.SizeBytes, failures, ref bytesFreed, ref appItemsRemoved);

        foreach (var item in leftoverItems)
        {
            TryTrash(item.FullPath, item.SizeBytes, failures, ref bytesFreed, ref leftoverItemsRemoved);
        }

        return new UninstallOutcome
        {
            App = app,
            AppRemoved = appRemoved,
            LeftoverItemsRemoved = leftoverItemsRemoved,
            BytesFreed = bytesFreed,
            Failures = failures
        };
    }

    public bool RunVendorUninstaller(InstalledApp app) =>
        throw new NotSupportedException(
            "macOS apps are removed directly via RemoveDirectly - there is no vendor uninstaller step.");

    private bool TryTrash(
        string path, long sizeBytes, List<CleanFailure> failures, ref long bytesFreed, ref int itemsRemoved)
    {
        if (!Guard.IsAllowed(path, out var reason))
        {
            failures.Add(new CleanFailure(path, $"blocked at removal-time: {reason}"));
            return false;
        }

        try
        {
            MoveToTrash(path);
            bytesFreed += sizeBytes;
            itemsRemoved++;
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            failures.Add(new CleanFailure(path, ex.Message));
            return false;
        }
    }

    private void MoveToTrash(string sourcePath)
    {
        var trashDir = _fileSystem.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".Trash");
        _fileSystem.Directory.CreateDirectory(trashDir);

        var baseName = _fileSystem.Path.GetFileName(sourcePath);
        var destPath = _fileSystem.Path.Combine(trashDir, baseName);

        // .Trash keeps a flat namespace - an item with the same name may already be
        // there from a previous delete, so find a free name rather than overwrite it.
        var counter = 1;
        while (_fileSystem.Directory.Exists(destPath) || _fileSystem.File.Exists(destPath))
        {
            var nameWithoutExt = _fileSystem.Path.GetFileNameWithoutExtension(baseName);
            var ext = _fileSystem.Path.GetExtension(baseName);
            destPath = _fileSystem.Path.Combine(trashDir, $"{nameWithoutExt} {counter}{ext}");
            counter++;
        }

        if (_fileSystem.Directory.Exists(sourcePath))
        {
            _fileSystem.Directory.Move(sourcePath, destPath);
        }
        else
        {
            _fileSystem.File.Move(sourcePath, destPath);
        }
    }
}
