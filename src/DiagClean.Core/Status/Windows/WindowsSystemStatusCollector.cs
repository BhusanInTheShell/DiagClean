using System.Diagnostics;
using System.Management;
using System.Runtime.Versioning;
using DiagClean.Core.Models;

namespace DiagClean.Core.Status.Windows;

/// <summary>
/// Windows counterpart to MacSystemStatusCollector - documented against known Windows
/// APIs (PerformanceCounter, WMI, Process) but not exercised on a real Windows machine
/// (see SMOKE_TEST.md), same as the rest of the Windows-only surface in this project.
/// No load average (see StatusModels.cs) and no per-core CPU breakdown, for the same
/// "keep it to what's reliably available without extra privilege" reasoning as the
/// macOS side.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WindowsSystemStatusCollector : ISystemStatusCollector
{
    private const int TopProcessCount = 5;

    public SystemStatusSnapshot Collect()
    {
        var cpuPercent = ReadCpuPercent();
        var (memUsedPercent, memUsedGb, memTotalGb) = ReadMemory();
        var (diskUsedPercent, diskFreeGb, diskTotalGb) = ReadDiskSpace();
        var diskActivity = ReadDiskActivity();
        var (downloadRate, uploadRate) = ReadNetworkThroughput();
        var (batteryPercent, batteryCharging) = ReadBattery();
        var topProcesses = ReadTopProcesses();

        return new SystemStatusSnapshot
        {
            CpuPercent = cpuPercent,
            MemoryUsedPercent = memUsedPercent,
            MemoryUsedGb = memUsedGb,
            MemoryTotalGb = memTotalGb,
            DiskUsedPercent = diskUsedPercent,
            DiskFreeGb = diskFreeGb,
            DiskTotalGb = diskTotalGb,
            DiskActivityBytesPerSecond = diskActivity,
            NetworkDownloadBytesPerSecond = downloadRate,
            NetworkUploadBytesPerSecond = uploadRate,
            BatteryPercent = batteryPercent,
            BatteryCharging = batteryCharging,
            TopProcesses = topProcesses
        };
    }

    private static double ReadCpuPercent()
    {
        try
        {
            using var counter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
            counter.NextValue();
            Thread.Sleep(1000);
            return counter.NextValue();
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            return 0;
        }
    }

    private static (double UsedPercent, double UsedGb, double TotalGb) ReadMemory()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT FreePhysicalMemory, TotalVisibleMemorySize FROM Win32_OperatingSystem");

            foreach (ManagementObject mo in searcher.Get().Cast<ManagementObject>())
            {
                var freeKb = Convert.ToDouble(mo["FreePhysicalMemory"]);
                var totalKb = Convert.ToDouble(mo["TotalVisibleMemorySize"]);
                if (totalKb <= 0)
                {
                    continue;
                }

                var usedPercent = (totalKb - freeKb) / totalKb * 100;
                return (usedPercent, (totalKb - freeKb) / 1024 / 1024, totalKb / 1024 / 1024);
            }
        }
        catch (ManagementException)
        {
            // WMI unavailable/misconfigured - degrade gracefully.
        }

        return (0, 0, 0);
    }

    private static (double UsedPercent, double FreeGb, double TotalGb) ReadDiskSpace()
    {
        try
        {
            var systemRoot = Path.GetPathRoot(Environment.SystemDirectory);
            if (systemRoot is null)
            {
                return (0, 0, 0);
            }

            var drive = new DriveInfo(systemRoot);
            var totalGb = drive.TotalSize / (1024d * 1024 * 1024);
            var freeGb = drive.AvailableFreeSpace / (1024d * 1024 * 1024);
            var usedPercent = totalGb > 0 ? (totalGb - freeGb) / totalGb * 100 : 0;
            return (usedPercent, freeGb, totalGb);
        }
        catch (IOException)
        {
            return (0, 0, 0);
        }
    }

    private static double ReadDiskActivity()
    {
        try
        {
            using var counter = new PerformanceCounter("PhysicalDisk", "Disk Bytes/sec", "_Total");
            counter.NextValue();
            Thread.Sleep(1000);
            return counter.NextValue();
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            return 0;
        }
    }

    private static (double DownloadBytesPerSecond, double UploadBytesPerSecond) ReadNetworkThroughput()
    {
        try
        {
            var category = new PerformanceCounterCategory("Network Interface");
            var instances = category.GetInstanceNames();

            using var downCounters = new CompositeDisposable<PerformanceCounter>(
                instances.Select(i => new PerformanceCounter("Network Interface", "Bytes Received/sec", i)));
            using var upCounters = new CompositeDisposable<PerformanceCounter>(
                instances.Select(i => new PerformanceCounter("Network Interface", "Bytes Sent/sec", i)));

            foreach (var c in downCounters.Items.Concat(upCounters.Items))
            {
                c.NextValue();
            }

            Thread.Sleep(1000);

            // Summed across every adapter instance rather than picking "the" primary
            // one - simpler and more robust than guessing which instance name
            // corresponds to the active adapter (loopback/virtual adapters report ~0
            // and don't meaningfully skew the total).
            var down = downCounters.Items.Sum(c => (double)c.NextValue());
            var up = upCounters.Items.Sum(c => (double)c.NextValue());
            return (down, up);
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            return (0, 0);
        }
    }

    private static (int? Percent, bool? Charging) ReadBattery()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT EstimatedChargeRemaining, BatteryStatus FROM Win32_Battery");

            foreach (ManagementObject mo in searcher.Get().Cast<ManagementObject>())
            {
                var percent = mo["EstimatedChargeRemaining"] is not null
                    ? Convert.ToInt32(mo["EstimatedChargeRemaining"])
                    : (int?)null;

                // BatteryStatus: 1 = Discharging; every other defined value (Charging,
                // Charging and High/Low/Critical, Fully Charged, etc.) implies the
                // machine is on AC power in some form.
                var status = mo["BatteryStatus"] is not null ? Convert.ToInt32(mo["BatteryStatus"]) : 0;
                var charging = status != 0 && status != 1;

                return (percent, charging);
            }
        }
        catch (ManagementException)
        {
            // No battery (most desktops) or WMI unavailable - not an error.
        }

        return (null, null);
    }

    private static IReadOnlyList<ProcessCpuUsage> ReadTopProcesses()
    {
        try
        {
            var processes = Process.GetProcesses();
            var startSamples = processes
                .Select(p => TryGetCpuSample(p))
                .Where(s => s is not null)
                .Select(s => s!.Value)
                .ToList();

            Thread.Sleep(500);

            var results = new List<ProcessCpuUsage>();
            var processorCount = Environment.ProcessorCount;
            var elapsedWallClock = TimeSpan.FromMilliseconds(500);

            foreach (var start in startSamples)
            {
                var endCpuTime = TryGetCpuSample(start.Process)?.CpuTime;
                if (endCpuTime is null)
                {
                    continue;
                }

                var cpuDelta = (endCpuTime.Value - start.CpuTime).TotalMilliseconds;
                var percent = cpuDelta / (elapsedWallClock.TotalMilliseconds * processorCount) * 100;

                results.Add(new ProcessCpuUsage(start.Process.ProcessName, Math.Max(0, percent)));
            }

            foreach (var p in startSamples.Select(s => s.Process))
            {
                p.Dispose();
            }

            return results.OrderByDescending(r => r.CpuPercent).Take(TopProcessCount).ToList();
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return [];
        }
    }

    private static (Process Process, TimeSpan CpuTime)? TryGetCpuSample(Process process)
    {
        try
        {
            return (process, process.TotalProcessorTime);
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
        {
            // Process exited or access denied (some system processes) between
            // enumeration and sampling - skip it rather than fail the whole list.
            return null;
        }
    }

    /// <summary>Disposes every counter in a collection together - PerformanceCounter
    /// doesn't implement IDisposable in a way IEnumerable&lt;T&gt; composes with directly.</summary>
    private sealed class CompositeDisposable<T> : IDisposable where T : IDisposable
    {
        public CompositeDisposable(IEnumerable<T> items) => Items = items.ToList();

        public List<T> Items { get; }

        public void Dispose()
        {
            foreach (var item in Items)
            {
                item.Dispose();
            }
        }
    }
}
