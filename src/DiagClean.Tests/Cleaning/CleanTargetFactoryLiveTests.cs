using System.IO.Abstractions;
using DiagClean.Core.Cleaning;
using Xunit;

namespace DiagClean.Tests.Cleaning;

/// <summary>
/// Scans (never deletes) against the real filesystem on macOS, where this suite actually
/// runs - regression coverage for the real path-resolution logic in CreateMacTargets that
/// MockFileSystem-based tests elsewhere in this file can't provide, since they only prove
/// the scanning algorithm is correct in the abstract, not that the concrete macOS paths
/// (~/Library/Application Support, ~/Library/Caches, /private/tmp) actually resolve and
/// scan without throwing on a real machine.
/// </summary>
public class CleanTargetFactoryLiveTests
{
    [Fact]
    public void Mac_targets_scan_the_real_filesystem_without_throwing()
    {
        if (!OperatingSystem.IsMacOS()) return;

        IFileSystem fileSystem = new FileSystem();
        var targets = CleanTargetFactory.CreateDefaultTargets(fileSystem);

        Assert.NotEmpty(targets);

        foreach (var target in targets)
        {
            var result = target.Scan();
            Assert.True(result.ItemCount >= 0);

            // The scan itself already ran every candidate through PathGuard - this is a
            // second, independent confirmation that nothing under a protected personal
            // folder (Desktop/Documents/Pictures/etc) ever made it into the result.
            Assert.All(result.Items, item => Assert.True(target.Guard.IsAllowed(item.FullPath, out _)));
        }
    }
}
