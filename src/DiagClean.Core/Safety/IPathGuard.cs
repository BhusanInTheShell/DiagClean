namespace DiagClean.Core.Safety;

public interface IPathGuard
{
    /// <summary>
    /// True if <paramref name="fullPath"/> may be scanned/deleted by a clean target.
    /// A path is allowed only if it is a descendant of one of the target's declared
    /// allowed roots AND does not match any protected path (built-in or user-configured).
    /// </summary>
    bool IsAllowed(string fullPath, out string? reason);
}
