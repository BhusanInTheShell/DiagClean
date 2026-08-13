namespace DiagClean.Core.Models;

public sealed record OptimizationResult
{
    public required bool Success { get; init; }
    public required string Message { get; init; }
}
