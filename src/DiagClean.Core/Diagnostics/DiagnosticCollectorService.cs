using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

/// <summary>
/// Orchestrates all collectors into one report. Each collector runs in isolation —
/// a failure in one (locked-down permissions, a missing WMI class, a disabled service)
/// is recorded as a <see cref="CollectorError"/> rather than aborting the whole run, so
/// a technician always gets a report, even if it's partial.
/// </summary>
public sealed class DiagnosticCollectorService
{
    private readonly IHardwareCollector _hardware;
    private readonly IDiskHealthCollector _disks;
    private readonly IEventLogCollector _eventLog;
    private readonly ISoftwareInventoryCollector _software;
    private readonly INetworkCollector _network;
    private readonly IPerformanceCollector _performance;

    public DiagnosticCollectorService(
        IHardwareCollector hardware,
        IDiskHealthCollector disks,
        IEventLogCollector eventLog,
        ISoftwareInventoryCollector software,
        INetworkCollector network,
        IPerformanceCollector performance)
    {
        _hardware = hardware;
        _disks = disks;
        _eventLog = eventLog;
        _software = software;
        _network = network;
        _performance = performance;
    }

    public DiagnosticReport Collect(string collectedBy)
    {
        var errors = new List<CollectorError>();

        var hardware = TryCollect("Hardware", _hardware.Collect, errors);
        var disks = TryCollect("Disk Health", _disks.Collect, errors) ?? [];
        var eventLogEntries = TryCollect("Event Log", () => _eventLog.Collect(), errors) ?? [];
        var software = TryCollect("Installed Software", _software.Collect, errors) ?? [];
        var network = TryCollect("Network Configuration", _network.Collect, errors) ?? [];
        var performance = TryCollect("Performance", _performance.Collect, errors);

        return new DiagnosticReport
        {
            MachineName = Environment.MachineName,
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = collectedBy,
            Hardware = hardware,
            Disks = disks,
            EventLogEntries = eventLogEntries,
            InstalledSoftware = software,
            NetworkAdapters = network,
            Performance = performance,
            CollectorErrors = errors
        };
    }

    private static T? TryCollect<T>(string collectorName, Func<T> collect, List<CollectorError> errors)
    {
        try
        {
            return collect();
        }
        catch (Exception ex)
        {
            errors.Add(new CollectorError(collectorName, ex.Message));
            return default;
        }
    }
}
