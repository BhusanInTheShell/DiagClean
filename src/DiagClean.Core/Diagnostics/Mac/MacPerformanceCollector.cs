using System.Runtime.Versioning;
using System.Text.RegularExpressions;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Diagnostics.Mac;

[SupportedOSPlatform("macos")]
public sealed class MacPerformanceCollector : IPerformanceCollector
{
    public PerformanceSnapshot Collect()
    {
        return new PerformanceSnapshot
        {
            CpuLoadPercent = Math.Round(ReadCpuLoad(), 1),
            MemoryUsedPercent = Math.Round(ReadMemoryUsedPercent(), 1),
            SystemUptimeHours = Math.Round(ReadUptimeHours(), 1),
            RecentApplicationCrashCount = CountRecentCrashReports()
        };
    }

    private static double ReadCpuLoad()
    {
        // `top -l 1` samples over its own short internal interval to compute a real
        // rate, unlike Windows' PerformanceCounter - no manual double-sample needed here.
        var output = ShellRunner.Run("top", ["-l", "1", "-n", "0"], timeout: TimeSpan.FromSeconds(10));
        if (output is null)
        {
            return 0;
        }

        // "CPU usage: 5.40% user, 10.81% sys, 83.78% idle"
        var match = Regex.Match(output, @"([\d.]+)%\s*idle");
        return match.Success && double.TryParse(match.Groups[1].Value, out var idle) ? 100 - idle : 0;
    }

    private static double ReadMemoryUsedPercent()
    {
        var pageSize = ReadSysctlLong("hw.pagesize");
        var totalBytes = ReadSysctlLong("hw.memsize");
        var vmStat = ShellRunner.Run("vm_stat", []);

        if (pageSize <= 0 || totalBytes <= 0 || vmStat is null)
        {
            return 0;
        }

        // Approximation, not an exact figure: macOS doesn't have a single documented
        // "% memory used" the way Windows does. "Active" + "wired" + "compressed" pages
        // is the commonly used proxy for memory under real pressure - "inactive",
        // "free", "speculative", and "purgeable" pages are all reclaimable/cached and
        // would overstate usage if counted as "used" the way Windows counts committed
        // memory.
        var active = ReadVmStatPages(vmStat, "Pages active");
        var wired = ReadVmStatPages(vmStat, "Pages wired down");
        var compressed = ReadVmStatPages(vmStat, "Pages occupied by compressor");

        var usedBytes = (active + wired + compressed) * pageSize;
        return usedBytes / (double)totalBytes * 100;
    }

    private static double ReadUptimeHours()
    {
        var boottime = ShellRunner.Run("sysctl", ["-n", "kern.boottime"]);
        if (boottime is null)
        {
            return 0;
        }

        // "{ sec = 1785054514, usec = 930401 } Sun Jul 26 18:28:34 2026" - the leading
        // numeric field is parsed directly rather than the trailing human-readable date,
        // which is locale-dependent formatting.
        var match = Regex.Match(boottime, @"sec\s*=\s*(\d+)");
        if (!match.Success || !long.TryParse(match.Groups[1].Value, out var bootEpochSeconds))
        {
            return 0;
        }

        var bootTime = DateTimeOffset.FromUnixTimeSeconds(bootEpochSeconds);
        return (DateTimeOffset.UtcNow - bootTime).TotalHours;
    }

    private static int CountRecentCrashReports()
    {
        try
        {
            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var dir = Path.Combine(home, "Library", "Logs", "DiagnosticReports");

            if (!Directory.Exists(dir))
            {
                return 0;
            }

            var cutoff = DateTime.UtcNow.AddHours(-24);

            // Top-level only - macOS moves older reports into a "Retired" subfolder,
            // which would skew a "recent" count if included.
            return Directory.EnumerateFiles(dir, "*", SearchOption.TopDirectoryOnly)
                .Where(f => f.EndsWith(".ips", StringComparison.OrdinalIgnoreCase) ||
                            f.EndsWith(".crash", StringComparison.OrdinalIgnoreCase))
                .Count(f => File.GetLastWriteTimeUtc(f) >= cutoff);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
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
