using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Cleaning;
using DiagClean.Core.Safety;
using Xunit;

namespace DiagClean.Tests.Cleaning;

public class SystemCachesTargetTests
{
    [Fact]
    public void Lists_top_level_cache_entries_as_individual_items()
    {
        var fs = new MockFileSystem();
        var cachesRoot = fs.Path.Combine(fs.Path.GetTempPath(), "Caches");
        var appCache = fs.Path.Combine(cachesRoot, "com.example.SomeApp");
        fs.AddFile(fs.Path.Combine(appCache, "blob"), new MockFileData("12345"));

        var guard = new PathGuard(fs, [cachesRoot], []);
        var target = new SystemCachesTarget(fs, guard, cachesRoot);

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == appCache);
    }

    [Fact]
    public void Excludes_entries_already_owned_by_browser_cache_target()
    {
        var fs = new MockFileSystem();
        var cachesRoot = fs.Path.Combine(fs.Path.GetTempPath(), "Caches");
        var googleDir = fs.Path.Combine(cachesRoot, "Google");
        var otherDir = fs.Path.Combine(cachesRoot, "com.example.SomeApp");
        fs.AddFile(fs.Path.Combine(googleDir, "f"), new MockFileData("x"));
        fs.AddFile(fs.Path.Combine(otherDir, "f"), new MockFileData("x"));

        var guard = new PathGuard(fs, [cachesRoot], []);
        var target = new SystemCachesTarget(fs, guard, cachesRoot, excludedTopLevelNames: ["Google"]);

        var result = target.Scan();

        Assert.DoesNotContain(result.Items, i => i.FullPath == googleDir);
        Assert.Contains(result.Items, i => i.FullPath == otherDir);
    }
}
