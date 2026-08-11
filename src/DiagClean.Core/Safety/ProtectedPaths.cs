using System.IO.Abstractions;

namespace DiagClean.Core.Safety;

/// <summary>
/// The built-in, non-overridable set of protected paths. Nothing in config can remove
/// these — user config can only add further protected paths on top.
///
/// Deliberately scoped to personal-data folders only (Desktop, Documents, Pictures,
/// Videos, Music) rather than broad system roots like UserProfile, Windows, or
/// ProgramFiles. Those broad roots are the *ancestors* of directories clean targets
/// legitimately need to reach - e.g. %TEMP% and browser caches live under the user
/// profile's AppData\Local, and the Windows Update cache lives under C:\Windows. Real
/// scoping for those targets comes from PathGuard's separate "allowed roots" allowlist
/// (each target hardcodes a narrow set of safe subfolders); this list exists purely to
/// veto personal files a bug could otherwise reach.
/// </summary>
public static class ProtectedPaths
{
    public static IReadOnlyList<string> GetBuiltIn(IFileSystem fileSystem)
    {
        var candidates = new[]
        {
            Environment.SpecialFolder.Desktop,
            Environment.SpecialFolder.DesktopDirectory,
            Environment.SpecialFolder.MyDocuments,
            Environment.SpecialFolder.MyPictures,
            Environment.SpecialFolder.MyVideos,
            Environment.SpecialFolder.MyMusic,
            Environment.SpecialFolder.CommonDesktopDirectory,
            Environment.SpecialFolder.CommonDocuments,
        };

        var result = new List<string>();
        foreach (var special in candidates)
        {
            var path = Environment.GetFolderPath(special);
            if (!string.IsNullOrWhiteSpace(path))
            {
                result.Add(fileSystem.Path.TrimEndingDirectorySeparator(path));
            }
        }

        return result;
    }
}
