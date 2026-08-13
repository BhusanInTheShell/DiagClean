namespace DiagClean.Core.Models;

public sealed record SystemStatusSnapshot
{
    public required double CpuPercent { get; init; }

    /// <summary>Null on Windows - load average is a Unix concept with no direct
    /// equivalent (Windows' closest analog, "Processor Queue Length", measures something
    /// different and shouldn't be mislabeled as the same statistic).</summary>
    public double? LoadAverage1Min { get; init; }
    public double? LoadAverage5Min { get; init; }
    public double? LoadAverage15Min { get; init; }
    public required double MemoryUsedPercent { get; init; }
    public required double MemoryUsedGb { get; init; }
    public required double MemoryTotalGb { get; init; }
    public required double DiskUsedPercent { get; init; }
    public required double DiskFreeGb { get; init; }
    public required double DiskTotalGb { get; init; }

    /// <summary>Combined read+write throughput - the underlying tools on both platforms
    /// (macOS's `iostat`, Windows' "Disk Bytes/sec" counter) report this as one figure,
    /// not a clean read/write split, so this is reported honestly as one number rather
    /// than fabricating a breakdown neither platform's tooling actually gives.</summary>
    public double DiskActivityBytesPerSecond { get; init; }

    public double NetworkDownloadBytesPerSecond { get; init; }
    public double NetworkUploadBytesPerSecond { get; init; }

    /// <summary>Null on machines with no battery (most desktops).</summary>
    public int? BatteryPercent { get; init; }
    public bool? BatteryCharging { get; init; }

    public required IReadOnlyList<ProcessCpuUsage> TopProcesses { get; init; }
}

public sealed record ProcessCpuUsage(string Name, double CpuPercent);
