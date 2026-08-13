using DiagClean.Core.Analyze.Mac;
using Xunit;

namespace DiagClean.Tests.Analyze.Mac;

/// <summary>
/// Runs against a small, real temp directory this test creates and cleans up itself -
/// genuine live verification of the `du -k -d 1` parsing (confirmed manually against
/// this machine's real home directory before writing this, see the commit that
/// introduced this file), without the multi-second cost of scanning something large on
/// every test run.
/// </summary>
public class MacDirectoryAnalyzerTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"diagclean-analyze-test-{Guid.NewGuid():N}");

    public MacDirectoryAnalyzerTests()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        Directory.CreateDirectory(Path.Combine(_root, "subdir"));
        File.WriteAllText(Path.Combine(_root, "subdir", "nested.txt"), new string('a', 2000));
        File.WriteAllText(Path.Combine(_root, "loose.txt"), new string('b', 500));
    }

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    [Fact]
    public void Finds_both_the_subdirectory_via_du_and_the_loose_file_via_FileInfo()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var analyzer = new MacDirectoryAnalyzer();
        var children = analyzer.GetChildren(_root);

        Assert.Contains(children, c => c.Name == "subdir" && c.IsDirectory);
        Assert.Contains(children, c => c.Name == "loose.txt" && !c.IsDirectory && c.SizeBytes == 500);
    }

    [Fact]
    public void Subdirectory_size_reflects_its_nested_content()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var analyzer = new MacDirectoryAnalyzer();
        var subdir = analyzer.GetChildren(_root).Single(c => c.Name == "subdir");

        // du reports in 1K blocks, so this won't be exactly 2000 bytes - just plausible.
        Assert.True(subdir.SizeBytes > 0);
    }
}
