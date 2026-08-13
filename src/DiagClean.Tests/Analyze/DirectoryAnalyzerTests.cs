using System.IO.Abstractions.TestingHelpers;
using DiagClean.Core.Analyze;
using Xunit;

namespace DiagClean.Tests.Analyze;

public class DirectoryAnalyzerTests
{
    [Fact]
    public void Lists_both_files_and_subdirectories_sorted_by_size_descending()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "root");

        fs.AddFile(fs.Path.Combine(root, "small.txt"), new MockFileData(new string('a', 10)));
        fs.AddFile(fs.Path.Combine(root, "big-folder", "f1"), new MockFileData(new string('b', 1000)));
        fs.AddFile(fs.Path.Combine(root, "medium.txt"), new MockFileData(new string('c', 100)));

        var analyzer = new DirectoryAnalyzer(fs);
        var children = analyzer.GetChildren(root);

        Assert.Equal(3, children.Count);
        Assert.Equal("big-folder", children[0].Name);
        Assert.True(children[0].IsDirectory);
        Assert.Equal(1000, children[0].SizeBytes);
        Assert.Equal("medium.txt", children[1].Name);
        Assert.False(children[1].IsDirectory);
        Assert.Equal("small.txt", children[2].Name);
    }

    [Fact]
    public void Returns_empty_list_for_a_directory_that_does_not_exist()
    {
        var fs = new MockFileSystem();
        var analyzer = new DirectoryAnalyzer(fs);

        var children = analyzer.GetChildren(fs.Path.Combine(fs.Path.GetTempPath(), "nowhere"));

        Assert.Empty(children);
    }

    [Fact]
    public void Empty_directory_returns_no_children_without_throwing()
    {
        var fs = new MockFileSystem();
        var root = fs.Path.Combine(fs.Path.GetTempPath(), "empty");
        fs.AddDirectory(root);

        var analyzer = new DirectoryAnalyzer(fs);
        var children = analyzer.GetChildren(root);

        Assert.Empty(children);
    }
}
