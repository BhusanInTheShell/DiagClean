using System.IO.Abstractions;

namespace DiagClean.Core.Shared;

/// <summary>
/// Moves a file or directory to ~/.Trash rather than deleting it outright - shared by
/// Uninstall (removing an app) and Analyze (removing whatever the user is currently
/// looking at) since both need the same "recoverable, not permanent" guarantee. .Trash
/// keeps a flat namespace, so an item with the same name may already be there from a
/// previous delete - this finds a free name rather than overwriting it.
/// </summary>
public static class MacTrash
{
    public static void Move(IFileSystem fileSystem, string sourcePath)
    {
        var trashDir = fileSystem.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".Trash");
        fileSystem.Directory.CreateDirectory(trashDir);

        var baseName = fileSystem.Path.GetFileName(sourcePath);
        var destPath = fileSystem.Path.Combine(trashDir, baseName);

        var counter = 1;
        while (fileSystem.Directory.Exists(destPath) || fileSystem.File.Exists(destPath))
        {
            var nameWithoutExt = fileSystem.Path.GetFileNameWithoutExtension(baseName);
            var ext = fileSystem.Path.GetExtension(baseName);
            destPath = fileSystem.Path.Combine(trashDir, $"{nameWithoutExt} {counter}{ext}");
            counter++;
        }

        if (fileSystem.Directory.Exists(sourcePath))
        {
            fileSystem.Directory.Move(sourcePath, destPath);
        }
        else
        {
            fileSystem.File.Move(sourcePath, destPath);
        }
    }
}
