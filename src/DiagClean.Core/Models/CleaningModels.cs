namespace DiagClean.Core.Models;

public enum CleanCategory
{
    TempFiles,
    BrowserCache,
    WindowsUpdate,
    InstallerLeftovers,
    SystemCaches
}

public sealed record CleanItem
{
    public required string FullPath { get; init; }
    public required CleanCategory Category { get; init; }
    public required long SizeBytes { get; init; }
    public bool IsDirectory { get; init; }
}

public sealed record ScanResult
{
    public required CleanCategory Category { get; init; }
    public required IReadOnlyList<CleanItem> Items { get; init; }
    public required IReadOnlyList<string> SkippedProtectedPaths { get; init; }
    public long TotalSizeBytes => Items.Sum(i => i.SizeBytes);
    public int ItemCount => Items.Count;
}

public sealed record CleanOutcome
{
    public required CleanCategory Category { get; init; }
    public required long BytesFreed { get; init; }
    public required int ItemsDeleted { get; init; }
    public required IReadOnlyList<CleanFailure> Failures { get; init; }
}

public sealed record CleanFailure(string FullPath, string Reason);

public enum CleanPreset
{
    Quick,
    Deep,
    Custom
}
