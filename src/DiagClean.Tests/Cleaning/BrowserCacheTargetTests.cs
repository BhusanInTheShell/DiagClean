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
        var chromeRoot = fs.Path.Combine(fs.Path.GetTempPath(), "Google", "Chrome", "User Data");
        var defaultCache = fs.Path.Combine(chromeRoot, "Default", "Cache");
        var profile1Cache = fs.Path.Combine(chromeRoot, "Profile 1", "Cache");
        var notAProfileCache = fs.Path.Combine(chromeRoot, "System Profile", "Cache");

        fs.AddFile(fs.Path.Combine(defaultCache, "f1"), new MockFileData("12345"));
        fs.AddFile(fs.Path.Combine(profile1Cache, "f2"), new MockFileData("1234567890"));
        fs.AddFile(fs.Path.Combine(notAProfileCache, "f3"), new MockFileData("x"));

        var guard = new PathGuard(fs, [chromeRoot], []);
        var target = new BrowserCacheTarget(fs, guard, chromiumProfileRoots: [chromeRoot], firefoxProfileParents: []);

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == defaultCache);
        Assert.Contains(result.Items, i => i.FullPath == profile1Cache);
        Assert.DoesNotContain(result.Items, i => i.FullPath == notAProfileCache);
    }

    [Fact]
    public void Finds_non_default_chromium_cache_subfolders_like_gpu_cache()
    {
        // Confirmed live on macOS: GPUCache/DawnWebGPUCache can exist even when the
        // classic "Cache" folder is momentarily absent - all known subfolder names
        // must be checked, not just "Cache".
        var fs = new MockFileSystem();
        var chromeRoot = fs.Path.Combine(fs.Path.GetTempPath(), "Chrome");
        var gpuCache = fs.Path.Combine(chromeRoot, "Default", "GPUCache");
        fs.AddFile(fs.Path.Combine(gpuCache, "f1"), new MockFileData("data"));

        var guard = new PathGuard(fs, [chromeRoot], []);
        var target = new BrowserCacheTarget(fs, guard, chromiumProfileRoots: [chromeRoot], firefoxProfileParents: []);

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == gpuCache);
    }

    [Fact]
    public void Finds_firefox_cache2_under_a_randomly_named_profile()
    {
        var fs = new MockFileSystem();
        var profilesRoot = fs.Path.Combine(fs.Path.GetTempPath(), "Firefox", "Profiles");
        var profileDir = fs.Path.Combine(profilesRoot, "abcd1234.default-release");
        var cacheDir = fs.Path.Combine(profileDir, "cache2");
        fs.AddFile(fs.Path.Combine(cacheDir, "entry1"), new MockFileData("hello"));

        var guard = new PathGuard(fs, [profilesRoot], []);
        var target = new BrowserCacheTarget(fs, guard, chromiumProfileRoots: [], firefoxProfileParents: [profilesRoot]);

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == cacheDir);
    }

    [Fact]
    public void Finds_standalone_cache_directory_like_safari()
    {
        var fs = new MockFileSystem();
        var safariCache = fs.Path.Combine(fs.Path.GetTempPath(), "com.apple.Safari");
        fs.AddFile(fs.Path.Combine(safariCache, "entry"), new MockFileData("x"));

        var guard = new PathGuard(fs, [safariCache], []);
        var target = new BrowserCacheTarget(
            fs, guard, chromiumProfileRoots: [], firefoxProfileParents: [], standaloneCacheDirs: [safariCache]);

        var result = target.Scan();

        Assert.Contains(result.Items, i => i.FullPath == safariCache);
    }
}
