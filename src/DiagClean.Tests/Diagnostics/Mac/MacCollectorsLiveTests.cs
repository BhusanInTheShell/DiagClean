using DiagClean.Core.Diagnostics.Mac;
using Xunit;

namespace DiagClean.Tests.Diagnostics.Mac;

/// <summary>
/// Unlike the Windows collectors (never exercised against a real Windows machine - see
/// SMOKE_TEST.md), these run against the real system every time the suite runs on macOS,
/// which it does in this repo's dev environment. They assert plausible shape rather than
/// exact values since machine specs vary, but a real macOS version bumping and breaking
/// `diskutil`/`system_profiler`/`log show` output format would show up here as a failure -
/// genuine regression coverage the Windows side doesn't have.
///
/// Each test soft-skips on non-macOS so the suite still passes if it's ever run on a
/// Windows/Linux CI agent, without pulling in a test-skip package for one guard clause.
/// </summary>
public class MacCollectorsLiveTests
{
    [Fact]
    public void Hardware_collector_returns_plausible_data()
    {
        if (!OperatingSystem.IsMacOS()) return;

        var info = new MacHardwareCollector().Collect();

        Assert.False(string.IsNullOrWhiteSpace(info.CpuName));
        Assert.True(info.CpuCores > 0);
        Assert.True(info.CpuLogicalProcessors > 0);
        Assert.True(info.TotalRamGb > 0);
        Assert.Equal("Apple", info.MotherboardManufacturer);
    }

    [Fact]
    public void Disk_health_collector_finds_at_least_the_boot_disk()
    {
        if (!OperatingSystem.IsMacOS()) return;

        var disks = new MacDiskHealthCollector().Collect();

        Assert.NotEmpty(disks);
        Assert.All(disks, d => Assert.True(d.SizeGb > 0));
    }

    [Fact]
    public void Performance_collector_returns_values_in_plausible_ranges()
    {
        if (!OperatingSystem.IsMacOS()) return;

        var perf = new MacPerformanceCollector().Collect();

        Assert.InRange(perf.CpuLoadPercent, 0, 100);
        Assert.InRange(perf.MemoryUsedPercent, 0, 100);
        Assert.True(perf.SystemUptimeHours >= 0);
        Assert.True(perf.RecentApplicationCrashCount >= 0);
    }

    [Fact]
    public void Software_inventory_collector_does_not_throw_and_returns_well_formed_entries()
    {
        if (!OperatingSystem.IsMacOS()) return;

        var software = new MacSoftwareInventoryCollector().Collect();

        Assert.All(software, s => Assert.False(string.IsNullOrWhiteSpace(s.Name)));
    }

    [Fact]
    public void System_log_collector_does_not_throw_and_respects_max_entries()
    {
        if (!OperatingSystem.IsMacOS()) return;

        var entries = new MacSystemLogCollector().Collect(maxEntries: 10);

        Assert.True(entries.Count <= 10);
        Assert.All(entries, e => Assert.Equal("Unified Log", e.LogName));
    }
}
