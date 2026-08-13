using System.IO.Abstractions;
using DiagClean.Core.Safety;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Builds the default set of clean targets for the current OS, each wired to its own
/// PathGuard scoped to only the roots that target legitimately needs. Keeping the guard
/// construction here (rather than inside each target) means every target's allowed-roots
/// list is visible in one place for review.
/// </summary>
public static class CleanTargetFactory
{
    public static IReadOnlyList<ICleanTarget> CreateDefaultTargets(
        IFileSystem fileSystem, IEnumerable<string>? extraProtectedPaths = null)
    {
        var protectedPaths = ProtectedPaths.GetBuiltIn(fileSystem)
            .Concat(extraProtectedPaths ?? [])
            .ToArray();

        return OperatingSystem.IsWindows()
            ? CreateWindowsTargets(fileSystem, protectedPaths)
            : CreateMacTargets(fileSystem, protectedPaths);
    }

    private static IReadOnlyList<ICleanTarget> CreateWindowsTargets(IFileSystem fileSystem, string[] protectedPaths)
    {
        var userTemp = fileSystem.Path.TrimEndingDirectorySeparator(fileSystem.Path.GetTempPath());
        var windowsDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var windowsTemp = fileSystem.Path.Combine(windowsDir, "Temp");
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        var tempRoots = new[] { userTemp, windowsTemp };

        return
        [
            new TempFilesTarget(
                fileSystem,
                new PathGuard(fileSystem, tempRoots, protectedPaths),
                tempRoots,
                requiresElevation: true),

            new BrowserCacheTarget(
                fileSystem,
                new PathGuard(fileSystem, [localAppData], protectedPaths),
                chromiumProfileRoots:
                [
                    fileSystem.Path.Combine(localAppData, "Google", "Chrome", "User Data"),
                    fileSystem.Path.Combine(localAppData, "Microsoft", "Edge", "User Data"),
                ],
                firefoxProfileParents:
                [
                    fileSystem.Path.Combine(localAppData, "Mozilla", "Firefox", "Profiles"),
                ]),

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

    private static IReadOnlyList<ICleanTarget> CreateMacTargets(IFileSystem fileSystem, string[] protectedPaths)
    {
        // Under `sudo`, Path.GetTempPath() resolves to *root's own* per-boot temp
        // namespace (live daemon sockets, not user junk) rather than the invoking
        // human's - ElevatedUserResolver corrects for that when applicable.
        var userTemp = fileSystem.Path.TrimEndingDirectorySeparator(
            ElevatedUserResolver.TryGetOriginalUserTempDir() ?? fileSystem.Path.GetTempPath());
        var sharedTemp = "/private/tmp";

        // Same concern as userTemp above: under `sudo`, whether HOME points at the
        // invoking user or at root depends on the machine's sudoers config - resolve
        // the real user's home explicitly rather than assume.
        var originalHome = ElevatedUserResolver.TryGetOriginalUserHomeDir();
        var appSupport = originalHome is not null // ~/Library/Application Support
            ? fileSystem.Path.Combine(originalHome, "Library", "Application Support")
            : Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var caches = originalHome is not null // ~/Library/Caches
            ? fileSystem.Path.Combine(originalHome, "Library", "Caches")
            : Environment.GetFolderPath(Environment.SpecialFolder.InternetCache);

        var tempRoots = new[] { userTemp, sharedTemp };
        var browserCacheExclusions = new[] { "Google", "Microsoft Edge", "Firefox", "com.apple.Safari" };

        return
        [
            new TempFilesTarget(
                fileSystem,
                new PathGuard(fileSystem, tempRoots, protectedPaths),
                tempRoots,
                requiresElevation: false),

            new BrowserCacheTarget(
                fileSystem,
                new PathGuard(fileSystem, [appSupport, caches], protectedPaths),
                chromiumProfileRoots:
                [
                    fileSystem.Path.Combine(appSupport, "Google", "Chrome"),
                    fileSystem.Path.Combine(appSupport, "Microsoft Edge"),
                ],
                firefoxProfileParents:
                [
                    fileSystem.Path.Combine(caches, "Firefox", "Profiles"),
                    fileSystem.Path.Combine(appSupport, "Firefox", "Profiles"),
                ],
                standaloneCacheDirs:
                [
                    fileSystem.Path.Combine(caches, "com.apple.Safari"),
                ]),

            new SystemCachesTarget(
                fileSystem,
                new PathGuard(fileSystem, [caches], protectedPaths),
                caches,
                excludedTopLevelNames: browserCacheExclusions),
        ];
    }
}
