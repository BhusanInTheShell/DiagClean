using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Cleaning;
using DiagClean.Core.Safety;
using Xunit;

namespace DiagClean.Tests.Cleaning;

public class InstallerLeftoverTargetTests
{
    [Fact]
    public void Matches_only_msi_msp_and_tmp_files()
    {
        var fs = new MockFileSystem();
        var tempRoot = fs.Path.Combine(fs.Path.GetTempPath(), "UserTemp");
        fs.AddFile(fs.Path.Combine(tempRoot, "installer.msi"), new MockFileData("a"));
        fs.AddFile(fs.Path.Combine(tempRoot, "patch.msp"), new MockFileData("b"));
        fs.AddFile(fs.Path.Combine(tempRoot, "leftover.tmp"), new MockFileData("c"));
        fs.AddFile(fs.Path.Combine(tempRoot, "notes.txt"), new MockFileData("d"));

        var guard = new PathGuard(fs, [tempRoot], []);
        var target = new InstallerLeftoverTarget(fs, guard, [tempRoot]);

        var result = target.Scan();

        Assert.Equal(3, result.ItemCount);
        Assert.DoesNotContain(result.Items, i => i.FullPath.EndsWith("notes.txt"));
    }
}
