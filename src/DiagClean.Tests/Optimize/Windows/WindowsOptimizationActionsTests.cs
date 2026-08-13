using DiagClean.Core.Optimize.Windows;
using Xunit;

namespace DiagClean.Tests.Optimize.Windows;

/// <summary>
/// WindowsOptimizationActions isn't [SupportedOSPlatform("windows")] (see its doc
/// comment), so unlike the Mac equivalent, these run unconditionally on any OS - same
/// "verify the action list's shape, never actually run one" reasoning as
/// MacOptimizationActionsTests, since RebuildIconCache/RestartExplorerAction/
/// ResetPrintSpooler all have real side effects that shouldn't fire as a byproduct of
/// running the test suite (and wouldn't work on this non-Windows dev machine anyway).
/// </summary>
public class WindowsOptimizationActionsTests
{
    [Fact]
    public void Every_action_has_a_name_and_description()
    {
        var actions = WindowsOptimizationActions.All;

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
        var names = WindowsOptimizationActions.All.Select(a => a.Name).ToList();
        Assert.Equal(names.Distinct().Count(), names.Count);
    }

    [Fact]
    public void Only_the_print_spooler_service_restart_requires_elevation()
    {
        // Killing/restarting explorer.exe and clearing your own AppData icon cache are
        // both your own user's own resources - only net stop/start on a system service
        // genuinely needs Administrator.
        var elevated = WindowsOptimizationActions.All.Where(a => a.RequiresElevation).ToList();

        Assert.Single(elevated);
        Assert.Contains("Print Spooler", elevated[0].Name);
    }

    [Fact]
    public void No_windows_action_is_flagged_slow()
    {
        // Unlike macOS's Spotlight reindex, none of these Windows actions take more
        // than a few seconds - documents that this platform currently has no "slow"
        // action requiring the CLI's separate confirmation step.
        Assert.DoesNotContain(WindowsOptimizationActions.All, a => a.IsSlow);
    }
}
