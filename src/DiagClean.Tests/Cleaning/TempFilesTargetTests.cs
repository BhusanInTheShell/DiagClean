using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Cleaning;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using Xunit;

namespace DiagClean.Tests.Cleaning;

public class TempFilesTargetTests
{
    [Fact]
    public void Scan_returns_top_level_files_and_directories_under_temp_roots()
    {
        var fs = new MockFileSystem();
        var tempRoot = fs.Path.Combine(fs.Path.GetTempPath(), "UserTemp");
        fs.AddFile(fs.Path.Combine(tempRoot, "a.tmp"), new MockFileData("12345"));
        fs.AddFile(fs.Path.Combine(tempRoot, "sub", "b.tmp"), new MockFileData("1234567890"));

        var guard = new PathGuard(fs, [tempRoot], []);
        var target = new TempFilesTarget(fs, guard, [tempRoot]);

        var result = target.Scan();

        Assert.Equal(CleanCategory.TempFiles, result.Category);
        Assert.Equal(2, result.ItemCount); // "a.tmp" file + "sub" directory, both top-level
        Assert.Contains(result.Items, i => i.FullPath == fs.Path.Combine(tempRoot, "a.tmp") && i.SizeBytes == 5);

        var subDirItem = result.Items.Single(i => i.IsDirectory);
        Assert.Equal(10, subDirItem.SizeBytes); // recursive size of everything under "sub"
    }

    [Fact]
    public void Scan_skips_items_blocked_by_the_guard_and_reports_them_as_skipped()
    {
        var fs = new MockFileSystem();
        var tempRoot = fs.Path.Combine(fs.Path.GetTempPath(), "UserTemp");
        var protectedSubDir = fs.Path.Combine(tempRoot, "DoNotTouch");
        fs.AddFile(fs.Path.Combine(tempRoot, "a.tmp"), new MockFileData("12345"));
        fs.AddFile(fs.Path.Combine(protectedSubDir, "secret.txt"), new MockFileData("shh"));

        var guard = new PathGuard(fs, [tempRoot], [protectedSubDir]);
        var target = new TempFilesTarget(fs, guard, [tempRoot]);

        var result = target.Scan();

        Assert.DoesNotContain(result.Items, i => i.FullPath == protectedSubDir);
        Assert.Contains(protectedSubDir, result.SkippedProtectedPaths);
        Assert.Contains(result.Items, i => i.FullPath == fs.Path.Combine(tempRoot, "a.tmp"));
    }
}
