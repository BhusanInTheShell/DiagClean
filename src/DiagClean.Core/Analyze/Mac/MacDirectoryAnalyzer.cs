using System.Runtime.Versioning;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Analyze.Mac;

/// <summary>
/// `du -k -d 1 <path>` gives every immediate subdirectory's recursive size in one fast
/// native call - dramatically faster than a managed recursive walk per navigation step
/// for large trees (~/Library, node_modules-laden project folders). Confirmed live:
/// output is tab-delimited "size\tpath" with one line per immediate subdirectory plus a
/// final summary line for the path itself, hidden directories included - but it does
/// NOT itemize loose files at the top level, so those are read directly via FileInfo.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacDirectoryAnalyzer : IDirectoryAnalyzer
{
    public IReadOnlyList<DiskEntry> GetChildren(string path)
    {
        var entries = new List<DiskEntry>();
        entries.AddRange(GetSubdirectories(path));
        entries.AddRange(GetLooseFiles(path));

        return entries.OrderByDescending(e => e.SizeBytes).ToList();
    }

    private static List<DiskEntry> GetSubdirectories(string path)
    {
        var results = new List<DiskEntry>();
        var output = ShellRunner.Run("du", ["-k", "-d", "1", path], TimeSpan.FromSeconds(30));
        if (output is null)
        {
            return results;
        }

        var normalizedRoot = Path.TrimEndingDirectorySeparator(path);

        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Split('\t', 2);
            if (parts.Length != 2 || !long.TryParse(parts[0], out var sizeKb))
            {
                continue;
            }

            var entryPath = parts[1];
            if (string.Equals(Path.TrimEndingDirectorySeparator(entryPath), normalizedRoot, StringComparison.Ordinal))
            {
                continue; // The summary line for `path` itself, not a child.
            }

            results.Add(new DiskEntry
            {
                Name = Path.GetFileName(entryPath),
                FullPath = entryPath,
                SizeBytes = sizeKb * 1024,
                IsDirectory = true,
                LastModified = TryGetLastModified(entryPath)
            });
        }

        return results;
    }

    private static List<DiskEntry> GetLooseFiles(string path)
    {
        var results = new List<DiskEntry>();
        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return results;
        }

        foreach (var file in files)
        {
            try
            {
                var info = new FileInfo(file);
                results.Add(new DiskEntry
                {
                    Name = info.Name,
                    FullPath = file,
                    SizeBytes = info.Length,
                    IsDirectory = false,
                    LastModified = info.LastWriteTime
                });
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Can't stat this one file - skip it rather than fail the whole listing.
            }
        }

        return results;
    }

    private static DateTime? TryGetLastModified(string path)
    {
        try
        {
            return Directory.GetLastWriteTime(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
