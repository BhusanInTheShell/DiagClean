using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Shared;

namespace DiagClean.Core.Analyze;

/// <summary>
/// Cross-platform, IFileSystem-based (and therefore fully unit-testable) default
/// implementation - a managed recursive walk for directory sizes. Used directly on
/// Windows; macOS uses the faster `du`-backed MacDirectoryAnalyzer instead, since a
/// managed walk over something like ~/Library can take noticeably longer than one
/// native `du` call.
/// </summary>
public sealed class DirectoryAnalyzer : IDirectoryAnalyzer
{
    private readonly IFileSystem _fileSystem;

    public DirectoryAnalyzer(IFileSystem fileSystem)
    {
        _fileSystem = fileSystem;
    }

    public IReadOnlyList<DiskEntry> GetChildren(string path)
    {
        var entries = new List<DiskEntry>();

        foreach (var dir in FileSystemScanHelpers.SafeGetDirectories(_fileSystem, path))
        {
            entries.Add(Describe(dir, isDirectory: true));
        }

        foreach (var file in FileSystemScanHelpers.SafeGetFiles(_fileSystem, path))
        {
            entries.Add(Describe(file, isDirectory: false));
        }

        return entries.OrderByDescending(e => e.SizeBytes).ToList();
    }

    private DiskEntry Describe(string path, bool isDirectory)
    {
        long size = 0;
        DateTime? modified = null;

        try
        {
            size = isDirectory
                ? FileSystemScanHelpers.DirectorySize(_fileSystem, path)
                : _fileSystem.FileInfo.New(path).Length;
            modified = isDirectory
                ? _fileSystem.Directory.GetLastWriteTime(path)
                : _fileSystem.FileInfo.New(path).LastWriteTime;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Can't stat it (locked, permission denied) - report 0/unknown rather than
            // drop it from the listing entirely; the user should still see it exists.
        }

        return new DiskEntry
        {
            Name = _fileSystem.Path.GetFileName(path),
            FullPath = path,
            SizeBytes = size,
            IsDirectory = isDirectory,
            LastModified = modified
        };
    }
}
