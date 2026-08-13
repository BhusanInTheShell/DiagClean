using System.IO.Abstractions;
using System.Runtime.Versioning;
using DiagClean.Core.Models;
using DiagClean.Core.Shared;

namespace DiagClean.Core.Analyze;

public enum DeleteMethod
{
    MovedToTrash,
    PermanentlyDeleted
}

public sealed record DeleteResult(bool Success, DeleteMethod Method, string? ErrorMessage);

/// <summary>
/// Analyze can navigate to and delete literally anything the user can see in the
/// filesystem - the least-scoped, highest-blast-radius surface in the app. Unlike
/// Clean/Uninstall, there's no fixed "allowed roots" list this could sensibly check
/// against (the whole point is browsing anywhere), so the safety net is procedural
/// instead: one item at a time, never a bulk multi-select, and the caller (the CLI
/// screen) is expected to show the full path and size and require an explicit typed
/// confirmation before calling Delete at all.
///
/// macOS moves to ~/.Trash (recoverable, via the same MacTrash helper Uninstall uses).
/// Windows permanently deletes - moving to the Recycle Bin from .NET means depending on
/// Microsoft.VisualBasic.FileIO, which this project has no way to verify actually builds
/// and works without a real Windows machine; shipping an unverified dependency for a
/// higher-stakes deletion path is worse than being upfront that it's permanent here.
/// </summary>
public static class AnalyzeDeleter
{
    public static DeleteResult Delete(IFileSystem fileSystem, DiskEntry entry)
    {
        if (OperatingSystem.IsMacOS())
        {
            return DeleteMac(fileSystem, entry);
        }

        return DeletePermanently(fileSystem, entry);
    }

    [SupportedOSPlatform("macos")]
    private static DeleteResult DeleteMac(IFileSystem fileSystem, DiskEntry entry)
    {
        try
        {
            MacTrash.Move(fileSystem, entry.FullPath);
            return new DeleteResult(true, DeleteMethod.MovedToTrash, null);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new DeleteResult(false, DeleteMethod.MovedToTrash, ex.Message);
        }
    }

    private static DeleteResult DeletePermanently(IFileSystem fileSystem, DiskEntry entry)
    {
        try
        {
            if (entry.IsDirectory)
            {
                fileSystem.Directory.Delete(entry.FullPath, recursive: true);
            }
            else
            {
                fileSystem.File.Delete(entry.FullPath);
            }

            return new DeleteResult(true, DeleteMethod.PermanentlyDeleted, null);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new DeleteResult(false, DeleteMethod.PermanentlyDeleted, ex.Message);
        }
    }
}
