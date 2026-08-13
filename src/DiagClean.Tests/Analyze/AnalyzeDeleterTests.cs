using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Analyze;
using DiagClean.Core.Models;
using Xunit;

namespace DiagClean.Tests.Analyze;

public class AnalyzeDeleterTests
{
    [Fact]
    public void Delete_removes_the_item_from_the_filesystem()
    {
        var fs = new MockFileSystem();
        var path = fs.Path.Combine(fs.Path.GetTempPath(), "target.txt");
        fs.AddFile(path, new MockFileData("data"));

        var entry = new DiskEntry { Name = "target.txt", FullPath = path, SizeBytes = 4, IsDirectory = false };
        var result = AnalyzeDeleter.Delete(fs, entry);

        Assert.True(result.Success);
        Assert.False(fs.File.Exists(path));
    }

    [Fact]
    public void Delete_uses_trash_move_on_macos_and_permanent_delete_elsewhere()
    {
        var fs = new MockFileSystem();
        var path = fs.Path.Combine(fs.Path.GetTempPath(), "target.txt");
        fs.AddFile(path, new MockFileData("data"));

        var entry = new DiskEntry { Name = "target.txt", FullPath = path, SizeBytes = 4, IsDirectory = false };
        var result = AnalyzeDeleter.Delete(fs, entry);

        var expectedMethod = OperatingSystem.IsMacOS() ? DeleteMethod.MovedToTrash : DeleteMethod.PermanentlyDeleted;
        Assert.Equal(expectedMethod, result.Method);

        if (expectedMethod == DeleteMethod.MovedToTrash)
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            Assert.True(fs.File.Exists(fs.Path.Combine(home, ".Trash", "target.txt")));
        }
    }

    [Fact]
    public void Delete_removes_a_directory_recursively()
    {
        var fs = new MockFileSystem();
        var dir = fs.Path.Combine(fs.Path.GetTempPath(), "target-dir");
        fs.AddFile(fs.Path.Combine(dir, "nested.txt"), new MockFileData("data"));

        var entry = new DiskEntry { Name = "target-dir", FullPath = dir, SizeBytes = 4, IsDirectory = true };
        var result = AnalyzeDeleter.Delete(fs, entry);

        Assert.True(result.Success);
        Assert.False(fs.Directory.Exists(dir));
    }

    [Fact]
    public void Delete_reports_failure_rather_than_throwing_for_a_nonexistent_path()
    {
        var fs = new MockFileSystem();
        var path = fs.Path.Combine(fs.Path.GetTempPath(), "does-not-exist.txt");

        var entry = new DiskEntry { Name = "does-not-exist.txt", FullPath = path, SizeBytes = 0, IsDirectory = false };
        var result = AnalyzeDeleter.Delete(fs, entry);

        Assert.False(result.Success);
        Assert.NotNull(result.ErrorMessage);
    }
}
