using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using DiagClean.Core.Uninstall;
using Xunit;

namespace DiagClean.Tests.Uninstall;

public class LeftoverScannerTests
{
    private static InstalledApp MakeApp(string identifier, string name) => new()
    {
        Name = name,
        Identifier = identifier,
        InstallPath = "/Applications/" + name + ".app",
        SizeBytes = 100
    };

    [Fact]
    public void Matches_entries_by_bundle_identifier_but_not_unrelated_entries()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Caches");
        var match = fs.Path.Combine(root, "com.example.TestApp");
        var unrelated = fs.Path.Combine(root, "com.other.Vendor");

        fs.AddFile(fs.Path.Combine(match, "f"), new MockFileData("data"));
        fs.AddFile(fs.Path.Combine(unrelated, "f"), new MockFileData("data"));

        var app = MakeApp("com.example.TestApp", "TestApp");
        var guard = new PathGuard(fs, [root], []);

        var result = LeftoverScanner.Scan(fs, guard, app, [root], [app.Identifier, app.Name]);

        Assert.Contains(result.Items, i => i.FullPath == match);
        Assert.DoesNotContain(result.Items, i => i.FullPath == unrelated);
    }

    [Fact]
    public void Matches_entries_by_app_name_when_identifier_does_not_match()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "LaunchAgents");
        var match = fs.Path.Combine(root, "TestApp-helper.plist");

        fs.AddFile(match, new MockFileData("x"));

        var app = MakeApp("com.example.TestApp", "TestApp");
        var guard = new PathGuard(fs, [root], []);

        var result = LeftoverScanner.Scan(fs, guard, app, [root], [app.Identifier, app.Name]);

        Assert.Contains(result.Items, i => i.FullPath == match);
    }

    [Fact]
    public void Skips_matches_that_fall_under_a_protected_path()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Caches");
        var protectedMatch = fs.Path.Combine(root, "com.example.TestApp");
        fs.AddFile(fs.Path.Combine(protectedMatch, "f"), new MockFileData("data"));

        var app = MakeApp("com.example.TestApp", "TestApp");
        var guard = new PathGuard(fs, [root], [protectedMatch]);

        var result = LeftoverScanner.Scan(fs, guard, app, [root], [app.Identifier, app.Name]);

        Assert.DoesNotContain(result.Items, i => i.FullPath == protectedMatch);
        Assert.Contains(protectedMatch, result.SkippedProtectedPaths);
    }

    [Fact]
    public void Does_not_recurse_into_unrelated_sibling_folders_contents()
    {
        // A file *inside* an unrelated app's folder that happens to mention this app's
        // name must not match - only top-level entry names under each root are checked.
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Caches");
        var unrelatedFolder = fs.Path.Combine(root, "com.other.Vendor");
        var nestedMention = fs.Path.Combine(unrelatedFolder, "TestApp-notes.txt");
        fs.AddFile(nestedMention, new MockFileData("mentions TestApp"));

        var app = MakeApp("com.example.TestApp", "TestApp");
        var guard = new PathGuard(fs, [root], []);

        var result = LeftoverScanner.Scan(fs, guard, app, [root], [app.Identifier, app.Name]);

        Assert.DoesNotContain(result.Items, i => i.FullPath == nestedMention);
    }
}
