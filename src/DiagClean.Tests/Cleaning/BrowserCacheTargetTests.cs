using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Cleaning;
using DiagClean.Core.Safety;
using Xunit;

namespace DiagClean.Tests.Cleaning;

public class BrowserCacheTargetTests
{
    [Fact]
    public void Finds_chrome_default_and_numbered_profile_caches_but_not_lookalikes()
    {
        var fs = new MockFileSystem();
        var localAppData = fs.Path.Combine(fs.Path.GetTempPath(), "LocalAppData");
        var chromeRoot = fs.Path.Combine(localAppData, "Google", "Chrome", "User Data");
        var defaultCache = fs.Path.Combine(chromeRoot, "Default", "Cache");
        var profile1Cache = fs.Path.Combine(chromeRoot, "Profile 1", "Cache");
        var notAProfileCache = fs.Path.Combine(chromeRoot, "System Profile", "Cache");

        fs.AddFile(fs.Path.Combine(defaultCache, "f1"), new MockFileData("12345"));
        fs.AddFile(fs.Path.Combine(profile1Cache, "f2"), new MockFileData("1234567890"));
        fs.AddFile(fs.Path.Combine(notAProfileCache, "f3"), new MockFileData("x"));

        var guard = new PathGuard(fs, [localAppData], []);
        var target = new BrowserCacheTarget(fs, guard, localAppData, fs.Path.Combine(fs.Path.GetTempPath(), "AppData"));

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == defaultCache);
        Assert.Contains(result.Items, i => i.FullPath == profile1Cache);
        Assert.DoesNotContain(result.Items, i => i.FullPath == notAProfileCache);
    }

    [Fact]
    public void Finds_firefox_cache2_under_a_randomly_named_profile()
    {
        var fs = new MockFileSystem();
        var localAppData = fs.Path.Combine(fs.Path.GetTempPath(), "LocalAppData");
        var profileDir = fs.Path.Combine(localAppData, "Mozilla", "Firefox", "Profiles", "abcd1234.default-release");
        var cacheDir = fs.Path.Combine(profileDir, "cache2");
        fs.AddFile(fs.Path.Combine(cacheDir, "entry1"), new MockFileData("hello"));

        var guard = new PathGuard(fs, [localAppData], []);
        var target = new BrowserCacheTarget(fs, guard, localAppData, fs.Path.Combine(fs.Path.GetTempPath(), "AppData"));

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == cacheDir);
    }
}
