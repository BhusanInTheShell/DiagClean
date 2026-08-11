namespace DiagClean.Core.Models;

public sealed record DiagnosticReport
{
    public required string MachineName { get; init; }
    public required DateTimeOffset GeneratedAt { get; init; }
    public required string CollectedBy { get; init; }
    public HardwareInfo? Hardware { get; init; }
    public IReadOnlyList<DiskInfo> Disks { get; init; } = [];
    public IReadOnlyList<EventLogEntryInfo> EventLogEntries { get; init; } = [];
    public IReadOnlyList<InstalledSoftware> InstalledSoftware { get; init; } = [];
    public IReadOnlyList<NetworkAdapterInfo> NetworkAdapters { get; init; } = [];
    public PerformanceSnapshot? Performance { get; init; }
    public IReadOnlyList<CollectorError> CollectorErrors { get; init; } = [];
}

public sealed record CollectorError(string CollectorName, string Message);

public sealed record HardwareInfo
{
    public string CpuName { get; init; } = "";
    public int CpuCores { get; init; }
    public int CpuLogicalProcessors { get; init; }
    public double TotalRamGb { get; init; }
    public string MotherboardManufacturer { get; init; } = "";
    public string MotherboardModel { get; init; } = "";
    public string BiosVersion { get; init; } = "";
    public IReadOnlyList<string> GpuNames { get; init; } = [];
}

public enum SmartStatus
{
    Unknown,
    Healthy,
    Warning,
    Failing
}

public sealed record DiskInfo
{
    public required string DeviceId { get; init; }
    public required string Model { get; init; }
    public double SizeGb { get; init; }
    public double FreeGb { get; init; }
    public SmartStatus SmartStatus { get; init; } = SmartStatus.Unknown;
    public string? SmartDetail { get; init; }
    public string MediaType { get; init; } = "Unknown";
}

public enum EventLogSeverity
{
    Warning,
    Error,
    Critical
}

public sealed record EventLogEntryInfo
{
    public required string LogName { get; init; }
    public required string Source { get; init; }
    public required EventLogSeverity Severity { get; init; }
    public required DateTimeOffset TimeGenerated { get; init; }
    public required string Message { get; init; }
    public int EventId { get; init; }
}

public sealed record InstalledSoftware
{
    public required string Name { get; init; }
    public string Version { get; init; } = "";
    public string Publisher { get; init; } = "";
    public DateOnly? InstallDate { get; init; }
}

public sealed record NetworkAdapterInfo
{
    public required string Name { get; init; }
    public string Description { get; init; } = "";
    public string MacAddress { get; init; } = "";
    public IReadOnlyList<string> IpAddresses { get; init; } = [];
    public IReadOnlyList<string> DnsServers { get; init; } = [];
    public string? Gateway { get; init; }
    public bool IsUp { get; init; }
}

public sealed record PerformanceSnapshot
{
    public double CpuLoadPercent { get; init; }
    public double MemoryUsedPercent { get; init; }
    public double SystemUptimeHours { get; init; }
    public int RecentApplicationCrashCount { get; init; }
}
