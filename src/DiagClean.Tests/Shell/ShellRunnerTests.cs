using DiagClean.Core.Shell;
using Xunit;

namespace DiagClean.Tests.Shell;

/// <summary>
/// RunWithExitCode is what Optimize's actions rely on to distinguish "the command ran
/// but failed" from "the command ran and succeeded" - unlike the older Run() (used by
/// the read-only Diagnostics collectors), where a nonzero exit code and an empty result
/// were treated the same ("nothing to parse"). /usr/bin/true and /usr/bin/false are
/// side-effect-free POSIX utilities that exist purely to have a known exit code, ideal
/// for testing this without touching real system state.
/// </summary>
public class ShellRunnerTests
{
    [Fact]
    public void RunWithExitCode_reports_success_for_a_zero_exit_code()
    {
        if (!OperatingSystem.IsMacOS() && !OperatingSystem.IsLinux())
        {
            return;
        }

        var result = ShellRunner.RunWithExitCode("true", []);

        Assert.True(result.Completed);
        Assert.Equal(0, result.ExitCode);
        Assert.True(result.Succeeded);
    }

    [Fact]
    public void RunWithExitCode_reports_failure_for_a_nonzero_exit_code()
    {
        if (!OperatingSystem.IsMacOS() && !OperatingSystem.IsLinux())
        {
            return;
        }

        var result = ShellRunner.RunWithExitCode("false", []);

        Assert.True(result.Completed);
        Assert.NotEqual(0, result.ExitCode);
        Assert.False(result.Succeeded);
    }

    [Fact]
    public void RunWithExitCode_reports_not_completed_for_a_missing_binary()
    {
        var result = ShellRunner.RunWithExitCode("this-binary-does-not-exist-anywhere", []);

        Assert.False(result.Completed);
        Assert.False(result.Succeeded);
    }

    [Fact]
    public void Run_still_returns_output_regardless_of_exit_code_unlike_RunWithExitCode()
    {
        // Documents the intentional behavior difference: Run() (the Diagnostics
        // collectors' method) doesn't care about exit code, only whether the process
        // completed - a command that fails but still writes to stdout should still
        // hand that output back.
        if (!OperatingSystem.IsMacOS() && !OperatingSystem.IsLinux())
        {
            return;
        }

        var output = ShellRunner.Run("sh", ["-c", "echo partial-output; exit 1"]);

        Assert.Equal("partial-output\n", output);
    }
}
