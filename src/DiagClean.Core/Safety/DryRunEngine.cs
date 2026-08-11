using System.IO.Abstractions;
using DiagClean.Core.Models;

namespace DiagClean.Core.Safety;

/// <summary>
/// Executes an already-scanned, already-confirmed <see cref="ScanResult"/>. This is the
/// only place in the codebase that deletes files. Every item is re-checked against its
/// guard immediately before deletion — the scan may be stale (seconds or minutes old by
/// the time a technician confirms), so nothing is trusted purely because it appeared in
/// the preview.
/// </summary>
public sealed class DryRunEngine
{
    private readonly IFileSystem _fileSystem;

    public DryRunEngine(IFileSystem fileSystem)
    {
        _fileSystem = fileSystem;
    }

    public CleanOutcome Execute(ScanResult scanResult, IPathGuard guard, IProgress<CleanItem>? progress = null)
    {
        long bytesFreed = 0;
        var itemsDeleted = 0;
        var failures = new List<CleanFailure>();

        foreach (var item in scanResult.Items)
        {
            if (!guard.IsAllowed(item.FullPath, out var reason))
            {
                failures.Add(new CleanFailure(item.FullPath, $"blocked at delete-time: {reason}"));
                continue;
            }

            try
            {
                if (item.IsDirectory)
                {
                    if (_fileSystem.Directory.Exists(item.FullPath))
                    {
                        _fileSystem.Directory.Delete(item.FullPath, recursive: true);
                    }
                }
                else if (_fileSystem.File.Exists(item.FullPath))
                {
                    _fileSystem.File.Delete(item.FullPath);
                }

                bytesFreed += item.SizeBytes;
                itemsDeleted++;
                progress?.Report(item);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                failures.Add(new CleanFailure(item.FullPath, ex.Message));
            }
        }

        return new CleanOutcome
        {
            Category = scanResult.Category,
            BytesFreed = bytesFreed,
            ItemsDeleted = itemsDeleted,
            Failures = failures
        };
    }
}
