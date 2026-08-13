using System.IO.Abstractions;
using System.Runtime.Versioning;
using DiagClean.Core.Safety;
using DiagClean.Core.Uninstall.Mac;
using DiagClean.Core.Uninstall.Windows;

namespace DiagClean.Core.Uninstall;

/// <summary>
/// Builds the OS-appropriate app lister and uninstaller, each wired to a PathGuard
/// scoped to only the roots Uninstall legitimately needs - same pattern as
/// Cleaning/CleanTargetFactory.
/// </summary>
public static class UninstallFactory
{
    public static (IAppLister Lister, IAppUninstaller Uninstaller) Create(
        IFileSystem fileSystem, IEnumerable<string>? extraProtectedPaths = null)
    {
        var protectedPaths = ProtectedPaths.GetBuiltIn(fileSystem)
            .Concat(extraProtectedPaths ?? [])
            .ToArray();

        // Calls into the OS-specific constructors below must stay directly inside these
        // guards (not factored into a ternary-to-helper-method, which the platform-
        // compatibility analyzer can't trace across) - same reasoning and pattern as
        // Composition.CreateDiagnosticService in the Cli project.
        if (OperatingSystem.IsWindows())
        {
            return CreateWindows(fileSystem, protectedPaths);
        }

        if (OperatingSystem.IsMacOS())
        {
            return CreateMac(fileSystem, protectedPaths);
        }

        throw new PlatformNotSupportedException("DiagClean supports Windows and macOS only.");
    }

    [SupportedOSPlatform("macos")]
    private static (IAppLister, IAppUninstaller) CreateMac(IFileSystem fileSystem, string[] protectedPaths)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var library = fileSystem.Path.Combine(home, "Library");

        var appRoots = new[]
        {
            "/Applications",
            fileSystem.Path.Combine(home, "Applications")
        };

        var leftoverRoots = new[]
        {
            fileSystem.Path.Combine(library, "Application Support"),
            fileSystem.Path.Combine(library, "Caches"),
            fileSystem.Path.Combine(library, "Preferences"),
            fileSystem.Path.Combine(library, "Logs"),
            fileSystem.Path.Combine(library, "Saved Application State"),
            fileSystem.Path.Combine(library, "WebKit"),
            fileSystem.Path.Combine(library, "HTTPStorages"),
            fileSystem.Path.Combine(library, "Containers"),
            fileSystem.Path.Combine(library, "Group Containers"),
            fileSystem.Path.Combine(library, "LaunchAgents"),
        };

        var guard = new PathGuard(fileSystem, appRoots.Concat(leftoverRoots), protectedPaths);

        return (
            new MacAppLister(fileSystem),
            new MacAppUninstaller(fileSystem, guard, leftoverRoots));
    }

    [SupportedOSPlatform("windows")]
    private static (IAppLister, IAppUninstaller) CreateWindows(IFileSystem fileSystem, string[] protectedPaths)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);

        var leftoverRoots = new[] { appData, localAppData, programData };
        var guard = new PathGuard(fileSystem, leftoverRoots, protectedPaths);

        return (
            new WindowsAppLister(),
            new WindowsAppUninstaller(fileSystem, guard, leftoverRoots));
    }
}
