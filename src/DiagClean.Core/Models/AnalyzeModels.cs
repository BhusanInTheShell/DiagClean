namespace DiagClean.Core.Models;

public sealed record DiskEntry
{
    public required string Name { get; init; }
    public required string FullPath { get; init; }
    public required long SizeBytes { get; init; }
    public required bool IsDirectory { get; init; }
    public DateTime? LastModified { get; init; }
}
