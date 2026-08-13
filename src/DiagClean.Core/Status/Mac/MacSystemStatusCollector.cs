using System.Runtime.Versioning;
using System.Text.RegularExpressions;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Status.Mac;

/// <summary>
/// Every metric here was verified against real output on this machine before being
/// wired in (see the commit that introduced this file) - `iostat -c 2 -w 1 disk0` in
/// particular does triple duty (CPU%, disk throughput, and load average all come back
/// in one combined table), which is why this collector doesn't reuse
/// MacPerformanceCollector's separate `top`-based CPU reading. No per-core CPU
/// breakdown: macOS has no reliable way to get that without `powermetrics`, which
/// requires root - out of scope for a quick status view that shouldn't need elevation.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacSystemStatusCollector : ISystemStatusCollector
{
    private const string PrimaryDisk = "disk0";
    private const int TopProcessCount = 5;

    public SystemStatusSnapshot Collect()
    {
        var (cpuPercent, loadAvg, diskActivity) = ReadIostat();
        var (memUsedPercent, memUsedGb, memTotalGb) = ReadMemory();
        var (diskUsedPercent, diskFreeGb, diskTotalGb) = ReadDiskSpace();
        var (batteryPercent, batteryCharging) = ReadBattery();
        var (downloadRate, uploadRate) = ReadNetworkThroughput();
        var topProcesses = ReadTopProcesses();

        return new SystemStatusSnapshot
        {
            CpuPercent = cpuPercent,
            LoadAverage1Min = loadAvg.OneMin,
            LoadAverage5Min = loadAvg.FiveMin,
            LoadAverage15Min = loadAvg.FifteenMin,
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

    private static (double CpuPercent, (double OneMin, double FiveMin, double FifteenMin) LoadAvg, double DiskActivityBytesPerSecond)
        ReadIostat()
    {
        // Two samples 1 second apart: the first line is the average since boot, the
        // second is the true last-second rate - only the last line is used.
        var output = ShellRunner.Run("iostat", ["-c", "2", "-w", "1", PrimaryDisk], TimeSpan.FromSeconds(10));
        if (output is null)
        {
            return (0, (0, 0, 0), 0);
        }

        var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        var lastDataLine = lines.LastOrDefault(l => l.TrimStart().Length > 0 && char.IsDigit(l.TrimStart()[0]));
        if (lastDataLine is null)
        {
            return (0, (0, 0, 0), 0);
        }

        // Columns: KB/t  tps  MB/s  us  sy  id  1m  5m  15m
        var fields = lastDataLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 9)
        {
            return (0, (0, 0, 0), 0);
        }

        double.TryParse(fields[2], out var mbPerSec);
        double.TryParse(fields[3], out var userPercent);
        double.TryParse(fields[4], out var sysPercent);
        double.TryParse(fields[6], out var load1);
        double.TryParse(fields[7], out var load5);
        double.TryParse(fields[8], out var load15);

        return (userPercent + sysPercent, (load1, load5, load15), mbPerSec * 1024 * 1024);
    }

    private static (double UsedPercent, double UsedGb, double TotalGb) ReadMemory()
    {
        var pageSize = ReadSysctlLong("hw.pagesize");
        var totalBytes = ReadSysctlLong("hw.memsize");
        var vmStat = ShellRunner.Run("vm_stat", []);

        if (pageSize <= 0 || totalBytes <= 0 || vmStat is null)
        {
            return (0, 0, 0);
        }

        // Same "active + wired + compressed" proxy as MacPerformanceCollector - see its
        // comment for why the other page categories are excluded.
        var active = ReadVmStatPages(vmStat, "Pages active");
        var wired = ReadVmStatPages(vmStat, "Pages wired down");
        var compressed = ReadVmStatPages(vmStat, "Pages occupied by compressor");

        var usedBytes = (active + wired + compressed) * pageSize;
        var totalGb = totalBytes / (1024d * 1024 * 1024);
        var usedGb = usedBytes / (1024d * 1024 * 1024);

        return (usedBytes / (double)totalBytes * 100, usedGb, totalGb);
    }

    private static (double UsedPercent, double FreeGb, double TotalGb) ReadDiskSpace()
    {
        try
        {
            var drive = new DriveInfo("/");
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

    private static (int? Percent, bool? Charging) ReadBattery()
    {
        var output = ShellRunner.Run("pmset", ["-g", "batt"], TimeSpan.FromSeconds(5));
        if (output is null)
        {
            return (null, null);
        }

        var match = Regex.Match(output, @"(\d+)%;\s*(charging|discharging|charged)");
        if (!match.Success)
        {
            return (null, null); // No battery present (desktop Mac) - not an error.
        }

        var percent = int.Parse(match.Groups[1].Value);
        var charging = !string.Equals(match.Groups[2].Value, "discharging", StringComparison.OrdinalIgnoreCase);
        return (percent, charging);
    }

    private static (double DownloadBytesPerSecond, double UploadBytesPerSecond) ReadNetworkThroughput()
    {
        var interfaceName = ReadDefaultInterface();
        if (interfaceName is null)
        {
            return (0, 0);
        }

        var first = ReadInterfaceCounters(interfaceName);
        Thread.Sleep(1000);
        var second = ReadInterfaceCounters(interfaceName);

        if (first is null || second is null)
        {
            return (0, 0);
        }

        var down = Math.Max(0, second.Value.InBytes - first.Value.InBytes);
        var up = Math.Max(0, second.Value.OutBytes - first.Value.OutBytes);
        return (down, up);
    }

    private static string? ReadDefaultInterface()
    {
        var output = ShellRunner.Run("route", ["get", "default"], TimeSpan.FromSeconds(5));
        var match = output is null ? null : Regex.Match(output, @"interface:\s*(\S+)");
        return match is { Success: true } ? match.Groups[1].Value : null;
    }

    private static (long InBytes, long OutBytes)? ReadInterfaceCounters(string interfaceName)
    {
        var output = ShellRunner.Run("netstat", ["-ib"], TimeSpan.FromSeconds(10));
        if (output is null)
        {
            return null;
        }

        // Only the raw <Link#N> row - the IPv4/IPv6 alias rows for the same interface
        // repeat the same cumulative counters, they'd just be redundant if included.
        var line = output.Split('\n')
            .FirstOrDefault(l => l.StartsWith(interfaceName + " ", StringComparison.Ordinal) && l.Contains("<Link#"));
        if (line is null)
        {
            return null;
        }

        // Column position shifts depending on whether the Address field is present -
        // parsing from the end of the line is robust to that, the trailing 7 numeric
        // columns (Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll) are always there.
        var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 7)
        {
            return null;
        }

        var inBytesOk = long.TryParse(fields[^5], out var inBytes);
        var outBytesOk = long.TryParse(fields[^2], out var outBytes);
        return inBytesOk && outBytesOk ? (inBytes, outBytes) : null;
    }

    private static IReadOnlyList<ProcessCpuUsage> ReadTopProcesses()
    {
        var output = ShellRunner.Run("ps", ["-Ao", "pid,pcpu", "-r"], TimeSpan.FromSeconds(10));
        if (output is null)
        {
            return [];
        }

        var results = new List<ProcessCpuUsage>();

        // Skip the header line; ps -r already sorts by %CPU descending.
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries).Skip(1).Take(TopProcessCount))
        {
            var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length < 2 || !double.TryParse(fields[1], out var cpuPercent))
            {
                continue;
            }

            var name = ReadProcessName(fields[0]) ?? $"pid {fields[0]}";
            results.Add(new ProcessCpuUsage(name, cpuPercent));
        }

        return results;
    }

    private static string? ReadProcessName(string pid)
    {
        // Scoped to a single PID, `comm` returns the full, untruncated path (confirmed
        // live) - unlike the fixed-width truncation `ps -Ao ... comm` applies when
        // listing multiple processes at once.
        var fullPath = ShellRunner.Run("ps", ["-p", pid, "-o", "comm="], TimeSpan.FromSeconds(5))?.Trim();
        return string.IsNullOrEmpty(fullPath) ? null : Path.GetFileName(fullPath);
    }

    private static long ReadVmStatPages(string vmStat, string label)
    {
        var line = vmStat.Split('\n').FirstOrDefault(l => l.TrimStart().StartsWith(label, StringComparison.OrdinalIgnoreCase));
        if (line is null)
        {
            return 0;
        }

        var digits = new string(line.Where(char.IsDigit).ToArray());
        return long.TryParse(digits, out var value) ? value : 0;
    }

    private static long ReadSysctlLong(string key)
    {
        var raw = ShellRunner.Run("sysctl", ["-n", key])?.Trim();
        return long.TryParse(raw, out var value) ? value : 0;
    }
}
