using System.IO.Abstractions;
using System.Runtime.Versioning;
using DiagClean.Core.Models;
using DiagClean.Core.Shared;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Uninstall.Mac;

/// <summary>
/// Lists user-removable apps from /Applications and ~/Applications only - deliberately
/// excludes /System/Applications (built-in OS apps aren't meant to be end-user
/// removable, and several aren't even relocatable/deletable without disabling SIP).
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacAppLister : IAppLister
{
    private readonly IFileSystem _fileSystem;

    public MacAppLister(IFileSystem fileSystem)
    {
        _fileSystem = fileSystem;
    }

    public IReadOnlyList<InstalledApp> ListApps()
    {
        var roots = new[]
        {
            "/Applications",
            _fileSystem.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Applications")
        };

        var apps = new List<InstalledApp>();
        foreach (var root in roots)
        {
            foreach (var bundlePath in FileSystemScanHelpers.SafeGetDirectories(_fileSystem, root, "*.app"))
            {
                var app = TryDescribe(bundlePath);
                if (app is not null)
                {
                    apps.Add(app);
                }
            }
        }

        return apps;
    }

    private InstalledApp? TryDescribe(string bundlePath)
    {
        var infoPlist = _fileSystem.Path.Combine(bundlePath, "Contents", "Info.plist");
        if (!_fileSystem.File.Exists(infoPlist))
        {
            // Not a real app bundle (e.g. a stray .app-suffixed folder) - skip it.
            return null;
        }

        var name = _fileSystem.Path.GetFileNameWithoutExtension(bundlePath);
        var identifier = ExtractPlistValue(infoPlist, "CFBundleIdentifier");
        if (string.IsNullOrWhiteSpace(identifier))
        {
            // No bundle identifier means leftover-file matching can't work reliably for
            // this app - still list it (by name-only matching) rather than hide it.
            identifier = name;
        }

        return new InstalledApp
        {
            Name = name,
            Identifier = identifier,
            InstallPath = bundlePath,
            Version = ExtractPlistValue(infoPlist, "CFBundleShortVersionString") ?? "",
            SizeBytes = ReadDirectorySizeKb(bundlePath) * 1024,
            LastModified = TryGetLastModified(bundlePath)
        };
    }

    private static string? ExtractPlistValue(string plistPath, string key) =>
        ShellRunner.Run("plutil", ["-extract", key, "raw", "-o", "-", plistPath], TimeSpan.FromSeconds(5))?.Trim();

    private static long ReadDirectorySizeKb(string path)
    {
        // `du -sk` is a single native call and dramatically faster than a managed
        // recursive file walk for large bundles (Xcode.app, IDEs, etc).
        var output = ShellRunner.Run("du", ["-sk", path], TimeSpan.FromSeconds(15));
        if (string.IsNullOrWhiteSpace(output))
        {
            return 0;
        }

        var firstField = output.Split('\t', ' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        return long.TryParse(firstField, out var kb) ? kb : 0;
    }

    private DateOnly? TryGetLastModified(string path)
    {
        try
        {
            return DateOnly.FromDateTime(_fileSystem.Directory.GetLastWriteTime(path));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
