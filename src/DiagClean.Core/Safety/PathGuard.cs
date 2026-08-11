using System.IO.Abstractions;

namespace DiagClean.Core.Safety;

/// <summary>
/// Enforces two independent checks before any path can be touched by a clean target:
///   1. It must be a descendant of one of the caller's declared allowed roots
///      (defense in depth against a target scanning somewhere it shouldn't).
///   2. It must not fall under a protected path, built-in or user-configured.
/// Both checks must pass. Neither list is meant to be exhaustive on its own.
/// </summary>
public sealed class PathGuard : IPathGuard
{
    private readonly IFileSystem _fileSystem;
    private readonly IReadOnlyList<string> _allowedRoots;
    private readonly IReadOnlyList<string> _protectedPaths;

    public PathGuard(
        IFileSystem fileSystem,
        IEnumerable<string> allowedRoots,
        IEnumerable<string> protectedPaths)
    {
        _fileSystem = fileSystem;
        _allowedRoots = allowedRoots.Select(Normalize).ToArray();
        _protectedPaths = protectedPaths.Select(Normalize).ToArray();
    }

    public bool IsAllowed(string fullPath, out string? reason)
    {
        string normalized;
        try
        {
            normalized = Normalize(fullPath);
        }
        catch (Exception ex) when (ex is ArgumentException or PathTooLongException or NotSupportedException)
        {
            reason = $"path could not be resolved: {ex.Message}";
            return false;
        }

        var protectedMatch = _protectedPaths.FirstOrDefault(p => IsSameOrDescendant(normalized, p));
        if (protectedMatch is not null)
        {
            reason = $"path is protected ({protectedMatch})";
            return false;
        }

        var insideAllowedRoot = _allowedRoots.Any(root => IsSameOrDescendant(normalized, root));
        if (!insideAllowedRoot)
        {
            reason = "path is outside the allowed roots for this clean target";
            return false;
        }

        reason = null;
        return true;
    }

    private string Normalize(string path)
    {
        var full = _fileSystem.Path.GetFullPath(path);
        return _fileSystem.Path.TrimEndingDirectorySeparator(full);
    }

    private bool IsSameOrDescendant(string candidate, string root)
    {
        var comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;

        if (string.Equals(candidate, root, comparison))
        {
            return true;
        }

        var rootWithSeparator = root + _fileSystem.Path.DirectorySeparatorChar;
        return candidate.StartsWith(rootWithSeparator, comparison);
    }
}
