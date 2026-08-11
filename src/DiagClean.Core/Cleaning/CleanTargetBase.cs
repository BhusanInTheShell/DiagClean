using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Shared scanning helpers for clean targets: every candidate path is checked against
/// the target's guard before it's even added to the scan result, and per-item failures
/// (locked files, permission denied) are swallowed into "skipped" rather than aborting
/// the whole scan - a single locked cache file should never hide the rest of the report.
/// </summary>
public abstract class CleanTargetBase
{
    protected readonly IFileSystem FileSystem;

    public IPathGuard Guard { get; }

    protected CleanTargetBase(IFileSystem fileSystem, IPathGuard guard)
    {
        FileSystem = fileSystem;
        Guard = guard;
    }

    protected ScanResult BuildScanResult(CleanCategory category, IEnumerable<string> candidatePaths)
    {
        var items = new List<CleanItem>();
        var skipped = new List<string>();

        foreach (var path in candidatePaths)
        {
            if (!Guard.IsAllowed(path, out _))
            {
                skipped.Add(path);
                continue;
            }

            var item = TryDescribe(category, path);
            if (item is not null)
            {
                items.Add(item);
            }
        }

        return new ScanResult
        {
            Category = category,
            Items = items,
            SkippedProtectedPaths = skipped
        };
    }

    private CleanItem? TryDescribe(CleanCategory category, string path)
    {
        try
        {
            if (FileSystem.Directory.Exists(path))
            {
                return new CleanItem
                {
                    FullPath = path,
                    Category = category,
                    SizeBytes = DirectorySize(path),
                    IsDirectory = true
                };
            }

            if (FileSystem.File.Exists(path))
            {
                return new CleanItem
                {
                    FullPath = path,
                    Category = category,
                    SizeBytes = FileSystem.FileInfo.New(path).Length,
                    IsDirectory = false
                };
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Can't stat it (locked, permission denied) - leave it out of the preview
            // rather than fail the whole scan.
        }

        return null;
    }

    private long DirectorySize(string path)
    {
        long total = 0;
        try
        {
            foreach (var file in FileSystem.Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
            {
                try
                {
                    total += FileSystem.FileInfo.New(file).Length;
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    // Skip individual locked/inaccessible files when sizing a directory.
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Directory became inaccessible mid-enumeration - report what we have.
        }

        return total;
    }

    protected IEnumerable<string> SafeGetDirectories(string root, string searchPattern = "*")
    {
        try
        {
            return FileSystem.Directory.Exists(root)
                ? FileSystem.Directory.GetDirectories(root, searchPattern)
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    protected IEnumerable<string> SafeGetFiles(string root, string searchPattern = "*")
    {
        try
        {
            return FileSystem.Directory.Exists(root)
                ? FileSystem.Directory.GetFiles(root, searchPattern)
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }
}
