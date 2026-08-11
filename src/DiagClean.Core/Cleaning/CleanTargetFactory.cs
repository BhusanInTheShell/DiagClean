using System.IO.Abstractions;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Builds the default set of clean targets, each wired to its own PathGuard scoped to
/// only the roots that target legitimately needs. Keeping the guard construction here
/// (rather than inside each target) means every target's allowed-roots list is visible
/// in one place for review.
/// </summary>
public static class CleanTargetFactory
{
    public static IReadOnlyList<ICleanTarget> CreateDefaultTargets(
        IFileSystem fileSystem, IEnumerable<string>? extraProtectedPaths = null)
    {
        var protectedPaths = ProtectedPaths.GetBuiltIn(fileSystem)
            .Concat(extraProtectedPaths ?? [])
            .ToArray();

        var userTemp = fileSystem.Path.TrimEndingDirectorySeparator(fileSystem.Path.GetTempPath());
        var windowsDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var windowsTemp = fileSystem.Path.Combine(windowsDir, "Temp");
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

        var tempRoots = new[] { userTemp, windowsTemp };

        return
        [
            new TempFilesTarget(
                fileSystem,
                new PathGuard(fileSystem, tempRoots, protectedPaths),
                tempRoots),

            new BrowserCacheTarget(
                fileSystem,
                new PathGuard(fileSystem, [localAppData], protectedPaths),
                localAppData,
                appData),

            new WindowsUpdateTarget(
                fileSystem,
                new PathGuard(
                    fileSystem,
                    [
                        fileSystem.Path.Combine(windowsDir, "SoftwareDistribution"),
                        fileSystem.Path.Combine(windowsDir, "ServiceProfiles"),
                    ],
                    protectedPaths),
                windowsDir),

            new InstallerLeftoverTarget(
                fileSystem,
                new PathGuard(fileSystem, tempRoots, protectedPaths),
                tempRoots),
        ];
    }
}
