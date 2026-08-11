using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Management;
using System.Runtime.Versioning;
using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

[SupportedOSPlatform("windows")]
public sealed class PerformanceCollector : IPerformanceCollector
{
    public PerformanceSnapshot Collect()
    {
        return new PerformanceSnapshot
        {
            CpuLoadPercent = Math.Round(ReadCpuLoad(), 1),
            MemoryUsedPercent = ReadMemoryAndUptime(out var uptimeHours),
            SystemUptimeHours = uptimeHours,
            RecentApplicationCrashCount = CountRecentApplicationCrashes()
        };
    }

    private static double ReadCpuLoad()
    {
        try
        {
            using var cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
            cpuCounter.NextValue();
            // The first read of this counter is always 0 - it needs two samples over an
            // interval to compute a rate. A short, blocking sleep is the standard fix.
            Thread.Sleep(500);
            return cpuCounter.NextValue();
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            // Performance counters can be disabled, corrupted, or have their backing registry
            // keys locked down by group policy - all of which surface as Win32Exception from
            // the counter constructor itself, not just from NextValue().
            return 0;
        }
    }

    private static double ReadMemoryAndUptime(out double uptimeHours)
    {
        double memUsedPercent = 0;
        uptimeHours = 0;

        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT FreePhysicalMemory, TotalVisibleMemorySize, LastBootUpTime FROM Win32_OperatingSystem");

            foreach (ManagementObject mo in searcher.Get().Cast<ManagementObject>())
            {
                var free = Convert.ToDouble(mo["FreePhysicalMemory"]);
                var total = Convert.ToDouble(mo["TotalVisibleMemorySize"]);
                if (total > 0)
                {
                    memUsedPercent = Math.Round((total - free) / total * 100, 1);
                }

                if (mo["LastBootUpTime"]?.ToString() is { Length: > 0 } bootTimeRaw)
                {
                    var bootTime = ManagementDateTimeConverter.ToDateTime(bootTimeRaw);
                    uptimeHours = Math.Round((DateTime.Now - bootTime).TotalHours, 1);
                }
            }
        }
        catch (ManagementException)
        {
            // WMI unavailable/misconfigured - degrade gracefully rather than fail the whole snapshot.
        }

        return memUsedPercent;
    }

    private static int CountRecentApplicationCrashes()
    {
        try
        {
            var cutoff = DateTime.UtcNow.AddHours(-24);
            var queryString =
                $"*[System[Provider[@Name='Application Error'] and " +
                $"TimeCreated[@SystemTime>='{cutoff:yyyy-MM-ddTHH:mm:ss.fffZ}']]]";

            var query = new EventLogQuery("Application", PathType.LogName, queryString);
            using var reader = new EventLogReader(query);

            var count = 0;
            while (reader.ReadEvent() is { } record)
            {
                using (record)
                {
                    count++;
                }
            }

            return count;
        }
        catch (EventLogNotFoundException)
        {
            return 0;
        }
    }
}
