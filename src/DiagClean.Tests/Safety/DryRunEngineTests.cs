using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using Xunit;

namespace DiagClean.Tests.Safety;

public class DryRunEngineTests
{
    [Fact]
    public void Deletes_allowed_items_and_sums_bytes_freed()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Root");
        var file1 = fs.Path.Combine(root, "a.txt");
        var file2 = fs.Path.Combine(root, "b.txt");
        fs.AddFile(file1, new MockFileData("12345"));
        fs.AddFile(file2, new MockFileData("1234567890"));

        var guard = new PathGuard(fs, [root], []);
        var scanResult = new ScanResult
        {
            Category = CleanCategory.TempFiles,
            Items =
            [
                new CleanItem { FullPath = file1, Category = CleanCategory.TempFiles, SizeBytes = 5, IsDirectory = false },
                new CleanItem { FullPath = file2, Category = CleanCategory.TempFiles, SizeBytes = 10, IsDirectory = false },
            ],
            SkippedProtectedPaths = []
        };

        var outcome = new DryRunEngine(fs).Execute(scanResult, guard);

        Assert.Equal(2, outcome.ItemsDeleted);
        Assert.Equal(15, outcome.BytesFreed);
        Assert.Empty(outcome.Failures);
        Assert.False(fs.FileExists(file1));
        Assert.False(fs.FileExists(file2));
    }

    [Fact]
    public void Blocks_deletion_of_an_item_outside_the_guard_even_if_present_in_the_scan_result()
    {
        // Defense-in-depth: the scan may be stale by the time a technician confirms.
        // Every item is re-checked against the guard immediately before deletion.
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Root");
        var outsidePath = fs.Path.Combine(fs.Path.GetTempPath(), "Outside", "important.txt");
        fs.AddFile(outsidePath, new MockFileData("data"));

        var guard = new PathGuard(fs, [root], []);
        var scanResult = new ScanResult
        {
            Category = CleanCategory.TempFiles,
            Items = [new CleanItem { FullPath = outsidePath, Category = CleanCategory.TempFiles, SizeBytes = 4, IsDirectory = false }],
            SkippedProtectedPaths = []
        };

        var outcome = new DryRunEngine(fs).Execute(scanResult, guard);

        Assert.Equal(0, outcome.ItemsDeleted);
        Assert.Single(outcome.Failures);
        Assert.True(fs.FileExists(outsidePath));
    }

    [Fact]
    public void Deletes_directories_recursively()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Root");
        var dir = fs.Path.Combine(root, "CacheDir");
        fs.AddFile(fs.Path.Combine(dir, "inner.txt"), new MockFileData("hello"));

        var guard = new PathGuard(fs, [root], []);
        var scanResult = new ScanResult
        {
            Category = CleanCategory.BrowserCache,
            Items = [new CleanItem { FullPath = dir, Category = CleanCategory.BrowserCache, SizeBytes = 5, IsDirectory = true }],
            SkippedProtectedPaths = []
        };

        var outcome = new DryRunEngine(fs).Execute(scanResult, guard);

        Assert.Equal(1, outcome.ItemsDeleted);
        Assert.False(fs.Directory.Exists(dir));
    }

    [Fact]
    public void Missing_item_produces_no_failure()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "Root");
        fs.AddDirectory(root);
        var missingFile = fs.Path.Combine(root, "already-gone.txt");

        var guard = new PathGuard(fs, [root], []);
        var scanResult = new ScanResult
        {
            Category = CleanCategory.TempFiles,
            Items = [new CleanItem { FullPath = missingFile, Category = CleanCategory.TempFiles, SizeBytes = 100, IsDirectory = false }],
            SkippedProtectedPaths = []
        };

        var outcome = new DryRunEngine(fs).Execute(scanResult, guard);

        Assert.Empty(outcome.Failures);
    }
}
