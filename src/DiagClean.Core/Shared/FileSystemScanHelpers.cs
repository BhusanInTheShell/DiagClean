using System.IO.Abstractions;

namespace DiagClean.Core.Shared;

/// <summary>
/// Filesystem enumeration/sizing helpers shared between Cleaning and Uninstall - both
/// need the same "don't crash the whole scan over one locked/inaccessible file or
/// directory" resilience, so it lives in one place rather than being copy-pasted.
/// </summary>
public static class FileSystemScanHelpers
{
    public static IEnumerable<string> SafeGetDirectories(IFileSystem fileSystem, string root, string searchPattern = "*")
    {
        try
        {
            return fileSystem.Directory.Exists(root)
                ? fileSystem.Directory.GetDirectories(root, searchPattern)
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    public static IEnumerable<string> SafeGetFiles(IFileSystem fileSystem, string root, string searchPattern = "*")
    {
        try
        {
            return fileSystem.Directory.Exists(root)
                ? fileSystem.Directory.GetFiles(root, searchPattern)
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    public static long DirectorySize(IFileSystem fileSystem, string path)
    {
        long total = 0;
        try
        {
            foreach (var file in fileSystem.Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
            {
                try
                {
                    total += fileSystem.FileInfo.New(file).Length;
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
}
