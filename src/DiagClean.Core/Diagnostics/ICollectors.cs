using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

public interface IHardwareCollector
{
    HardwareInfo Collect();
}

public interface IDiskHealthCollector
{
    IReadOnlyList<DiskInfo> Collect();
}

public interface IEventLogCollector
{
    IReadOnlyList<EventLogEntryInfo> Collect(int maxAgeDays = 7, int maxEntries = 200);
}

public interface ISoftwareInventoryCollector
{
    IReadOnlyList<InstalledSoftware> Collect();
}

public interface INetworkCollector
{
    IReadOnlyList<NetworkAdapterInfo> Collect();
}

public interface IPerformanceCollector
{
    PerformanceSnapshot Collect();
}
