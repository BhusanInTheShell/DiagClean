using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using DiagClean.Core.Uninstall.Mac;
using Xunit;

namespace DiagClean.Tests.Uninstall.Mac;

/// <summary>
/// MacAppUninstaller is [SupportedOSPlatform("macos")] since its production factory
/// resolves real macOS paths - each test soft-skips on non-macOS the same way
/// MacCollectorsLiveTests does, which the platform-compatibility analyzer recognizes as
/// a valid guard. Everything here uses MockFileSystem, so no real files are ever moved.
/// </summary>
public class MacAppUninstallerTests
{
    private static InstalledApp MakeApp(string appPath, string identifier, long sizeBytes = 1000) => new()
    {
        Name = "TestApp",
        Identifier = identifier,
        InstallPath = appPath,
        SizeBytes = sizeBytes
    };

    [Fact]
    public void Moves_app_and_leftovers_to_trash_rather_than_deleting_them()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var fs = new MockFileSystem();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appsRoot = "/Applications";
        var appPath = fs.Path.Combine(appsRoot, "TestApp.app");
        var cachesRoot = fs.Path.Combine(home, "Library", "Caches");
        var leftoverPath = fs.Path.Combine(cachesRoot, "com.example.TestApp");

        fs.AddFile(fs.Path.Combine(appPath, "Contents", "Info.plist"), new MockFileData("x"));
        fs.AddFile(fs.Path.Combine(leftoverPath, "f"), new MockFileData("data"));

        var app = MakeApp(appPath, "com.example.TestApp");
        var guard = new PathGuard(fs, [appsRoot, cachesRoot], []);
        var uninstaller = new MacAppUninstaller(fs, guard, [cachesRoot]);

        var leftoverItem = new AppLeftoverItem { FullPath = leftoverPath, SizeBytes = 500, IsDirectory = true };
        var outcome = uninstaller.RemoveDirectly(app, [leftoverItem]);

        Assert.True(outcome.AppRemoved);
        Assert.Equal(1, outcome.LeftoverItemsRemoved);
        Assert.Empty(outcome.Failures);
        Assert.False(fs.Directory.Exists(appPath));
        Assert.False(fs.Directory.Exists(leftoverPath));

        var trashDir = fs.Path.Combine(home, ".Trash");
        Assert.True(fs.Directory.Exists(fs.Path.Combine(trashDir, "TestApp.app")));
        Assert.True(fs.Directory.Exists(fs.Path.Combine(trashDir, "com.example.TestApp")));
    }

    [Fact]
    public void Avoids_overwriting_an_existing_trash_entry_with_the_same_name()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var fs = new MockFileSystem();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appsRoot = "/Applications";
        var appPath = fs.Path.Combine(appsRoot, "TestApp.app");
        var trashDir = fs.Path.Combine(home, ".Trash");
        var existingTrashEntry = fs.Path.Combine(trashDir, "TestApp.app");

        fs.AddFile(fs.Path.Combine(appPath, "Contents", "Info.plist"), new MockFileData("x"));
        fs.AddFile(fs.Path.Combine(existingTrashEntry, "old-marker"), new MockFileData("already here"));

        var app = MakeApp(appPath, "com.example.TestApp");
        var guard = new PathGuard(fs, [appsRoot], []);
        var uninstaller = new MacAppUninstaller(fs, guard, []);

        var outcome = uninstaller.RemoveDirectly(app, []);

        Assert.True(outcome.AppRemoved);
        // The pre-existing Trash entry must survive untouched, and the newly-moved one
        // must land under a disambiguated name rather than overwrite it.
        Assert.True(fs.File.Exists(fs.Path.Combine(existingTrashEntry, "old-marker")));
        Assert.True(fs.Directory.Exists(fs.Path.Combine(trashDir, "TestApp 1.app")));
    }

    [Fact]
    public void Reports_a_failure_instead_of_removing_a_path_outside_the_allowed_roots()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var fs = new MockFileSystem();
        var appsRoot = "/Applications";
        var appPath = fs.Path.Combine(appsRoot, "TestApp.app");
        fs.AddFile(fs.Path.Combine(appPath, "Contents", "Info.plist"), new MockFileData("x"));

        var app = MakeApp(appPath, "com.example.TestApp");
        // Guard only allows a completely unrelated root - the app path itself isn't covered.
        var guard = new PathGuard(fs, ["/some/other/root"], []);
        var uninstaller = new MacAppUninstaller(fs, guard, []);

        var outcome = uninstaller.RemoveDirectly(app, []);

        Assert.False(outcome.AppRemoved);
        Assert.Single(outcome.Failures);
        Assert.True(fs.Directory.Exists(appPath));
    }
}
