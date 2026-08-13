namespace DiagClean.Core.Models;

/// <summary>
/// An app discoverable through the OS's own app registry - macOS's /Applications (or
/// ~/Applications) bundles, Windows's registry Uninstall keys. <see cref="Identifier"/>
/// is what leftover-file matching keys off: a bundle identifier (e.g.
/// "com.adobe.Photoshop") on macOS, or the registry's UninstallString on Windows.
/// </summary>
public sealed record InstalledApp
{
    public required string Name { get; init; }
    public required string Identifier { get; init; }
    public required string InstallPath { get; init; }
    public string Version { get; init; } = "";
    public string Publisher { get; init; } = "";
    public long SizeBytes { get; init; }
    public DateOnly? LastModified { get; init; }
}

public sealed record AppLeftoverItem
{
    public required string FullPath { get; init; }
    public required long SizeBytes { get; init; }
    public bool IsDirectory { get; init; }
}

public sealed record AppLeftoverScanResult
{
    public required InstalledApp App { get; init; }
    public required IReadOnlyList<AppLeftoverItem> Items { get; init; }
    public required IReadOnlyList<string> SkippedProtectedPaths { get; init; }
    public long TotalSizeBytes => Items.Sum(i => i.SizeBytes);
    public int ItemCount => Items.Count;
}

public sealed record UninstallOutcome
{
    public required InstalledApp App { get; init; }
    public required bool AppRemoved { get; init; }
    public required int LeftoverItemsRemoved { get; init; }
    public required long BytesFreed { get; init; }
    public required IReadOnlyList<CleanFailure> Failures { get; init; }
}
