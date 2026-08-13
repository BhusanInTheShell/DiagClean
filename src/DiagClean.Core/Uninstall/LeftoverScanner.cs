using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using DiagClean.Core.Shared;

namespace DiagClean.Core.Uninstall;

/// <summary>
/// Shared "does this file/folder belong to this app" scanning logic for Uninstall - only
/// the set of candidate roots and match tokens (bundle identifier, display name) differs
/// per platform. A candidate root's immediate children are checked by name, not walked
/// recursively - leftover roots like ~/Library/Caches contain one folder per app, so a
/// deep walk would be both slow and wrong (it would match files *inside* unrelated apps'
/// folders whose contents happen to mention this app's name).
/// </summary>
public static class LeftoverScanner
{
    public static AppLeftoverScanResult Scan(
        IFileSystem fileSystem,
        IPathGuard guard,
        InstalledApp app,
        IEnumerable<string> candidateRoots,
        IEnumerable<string> matchTokens)
    {
        var tokens = matchTokens.Where(t => !string.IsNullOrWhiteSpace(t)).ToArray();
        var items = new List<AppLeftoverItem>();
        var skipped = new List<string>();

        foreach (var root in candidateRoots)
        {
            var entries = FileSystemScanHelpers.SafeGetDirectories(fileSystem, root)
                .Concat(FileSystemScanHelpers.SafeGetFiles(fileSystem, root));

            foreach (var entryPath in entries)
            {
                var entryName = fileSystem.Path.GetFileName(entryPath);
                if (!tokens.Any(t => entryName.Contains(t, StringComparison.OrdinalIgnoreCase)))
                {
                    continue;
                }

                if (!guard.IsAllowed(entryPath, out _))
                {
                    skipped.Add(entryPath);
                    continue;
                }

                var item = Describe(fileSystem, entryPath);
                if (item is not null)
                {
                    items.Add(item);
                }
            }
        }

        return new AppLeftoverScanResult
        {
            App = app,
            Items = items,
            SkippedProtectedPaths = skipped
        };
    }

    private static AppLeftoverItem? Describe(IFileSystem fileSystem, string path)
    {
        try
        {
            if (fileSystem.Directory.Exists(path))
            {
                return new AppLeftoverItem
                {
                    FullPath = path,
                    SizeBytes = FileSystemScanHelpers.DirectorySize(fileSystem, path),
                    IsDirectory = true
                };
            }

            if (fileSystem.File.Exists(path))
            {
                return new AppLeftoverItem
                {
                    FullPath = path,
                    SizeBytes = fileSystem.FileInfo.New(path).Length,
                    IsDirectory = false
                };
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Can't stat it (locked, permission denied) - leave it out rather than fail the whole scan.
        }

        return null;
    }
}
