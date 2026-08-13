using DiagClean.Core.Optimize.Mac;
using Xunit;

namespace DiagClean.Tests.Optimize.Mac;

/// <summary>
/// Deliberately does not call Run() on any action here - unlike Diagnostics (read-only)
/// or Cleaning/Uninstall (tested via MockFileSystem, never touching a real file),
/// Optimize's actions have real, non-mockable side effects on live system state
/// (restarting Finder/Dock, flushing caches). Actually running them as part of the
/// automated suite would side-effect whoever's machine runs `dotnet test` as a byproduct
/// of testing - the safe, non-elevated actions were verified manually against this
/// machine instead (see the commit that introduced this file).
/// </summary>
public class MacOptimizationActionsTests
{
    [Fact]
    public void Every_action_has_a_name_and_description()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var actions = MacOptimizationActions.All;

        Assert.NotEmpty(actions);
        Assert.All(actions, a =>
        {
            Assert.False(string.IsNullOrWhiteSpace(a.Name));
            Assert.False(string.IsNullOrWhiteSpace(a.Description));
        });
    }

    [Fact]
    public void Action_names_are_unique()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var names = MacOptimizationActions.All.Select(a => a.Name).ToList();
        Assert.Equal(names.Distinct().Count(), names.Count);
    }

    [Fact]
    public void The_slow_reindex_action_is_flagged_slow_and_elevated()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var spotlight = MacOptimizationActions.All.Single(a => a.Name.Contains("Spotlight"));

        Assert.True(spotlight.IsSlow);
        Assert.True(spotlight.RequiresElevation);
    }

    [Fact]
    public void Finder_and_dock_restart_does_not_require_elevation()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        // Killing your own user's own processes never needs root - this documents that
        // assumption so a future change that accidentally marks it elevated fails loudly.
        var restart = MacOptimizationActions.All.Single(a => a.Name.Contains("Finder"));

        Assert.False(restart.RequiresElevation);
        Assert.False(restart.IsSlow);
    }
}
