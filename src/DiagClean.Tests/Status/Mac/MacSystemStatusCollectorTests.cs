using DiagClean.Core.Status.Mac;
using Xunit;

namespace DiagClean.Tests.Status.Mac;

/// <summary>
/// Unlike Optimize's actions, Status is read-only - collecting a snapshot has no side
/// effects beyond the ~2 seconds the underlying sampling takes (confirmed live against
/// this machine, see the commit that introduced this file), so it's safe to actually
/// run for real here, same reasoning as the Diagnostics collectors' live tests.
/// </summary>
public class MacSystemStatusCollectorTests
{
    [Fact]
    public void Collect_returns_plausible_values_for_every_metric()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var snapshot = new MacSystemStatusCollector().Collect();

        Assert.InRange(snapshot.CpuPercent, 0, 100);
        Assert.True(snapshot.LoadAverage1Min is >= 0);
        Assert.InRange(snapshot.MemoryUsedPercent, 0, 100);
        Assert.True(snapshot.MemoryTotalGb > 0);
        Assert.True(snapshot.MemoryUsedGb <= snapshot.MemoryTotalGb);
        Assert.InRange(snapshot.DiskUsedPercent, 0, 100);
        Assert.True(snapshot.DiskTotalGb > 0);
        Assert.True(snapshot.DiskActivityBytesPerSecond >= 0);
        Assert.True(snapshot.NetworkDownloadBytesPerSecond >= 0);
        Assert.True(snapshot.NetworkUploadBytesPerSecond >= 0);
        Assert.NotEmpty(snapshot.TopProcesses);
    }

    [Fact]
    public void Top_processes_are_sorted_by_cpu_percent_descending_with_real_names()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var snapshot = new MacSystemStatusCollector().Collect();

        Assert.All(snapshot.TopProcesses, p => Assert.False(string.IsNullOrWhiteSpace(p.Name)));
        // ps -r already sorts by %CPU - this would catch a parsing regression that broke that ordering.
        for (var i = 1; i < snapshot.TopProcesses.Count; i++)
        {
            Assert.True(snapshot.TopProcesses[i - 1].CpuPercent >= snapshot.TopProcesses[i].CpuPercent);
        }
    }

    [Fact]
    public void Battery_is_either_fully_absent_or_a_plausible_percentage()
    {
        if (!OperatingSystem.IsMacOS())
        {
            return;
        }

        var snapshot = new MacSystemStatusCollector().Collect();

        if (snapshot.BatteryPercent is { } percent)
        {
            Assert.InRange(percent, 0, 100);
            Assert.NotNull(snapshot.BatteryCharging);
        }
        else
        {
            Assert.Null(snapshot.BatteryCharging);
        }
    }
}
