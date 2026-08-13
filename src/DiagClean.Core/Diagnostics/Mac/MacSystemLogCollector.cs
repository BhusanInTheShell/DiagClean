using System.Runtime.Versioning;
using System.Text.Json;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Diagnostics.Mac;

/// <summary>
/// Reads macOS's unified log - one stream for everything, unlike Windows' separate
/// Application/System event logs. messageType 16/17 are Error/Fault, the closest
/// equivalents to Windows Event Log's Error/Critical levels.
///
/// The query window is capped at 24h regardless of the requested maxAgeDays: `log show`
/// over multi-day windows can take minutes and return tens of thousands of lines on a
/// busy Mac, which isn't practical for an interactive tool. 24h of errors/faults is
/// still the highest-signal window for "why is this machine acting up right now" triage.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacSystemLogCollector : IEventLogCollector
{
    private const string LogSourceName = "Unified Log";

    public IReadOnlyList<EventLogEntryInfo> Collect(int maxAgeDays = 7, int maxEntries = 200)
    {
        var output = ShellRunner.Run(
            "log",
            ["show", "--predicate", "messageType == 16 OR messageType == 17", "--last", "24h", "--style", "ndjson"],
            timeout: TimeSpan.FromSeconds(30));

        if (output is null)
        {
            return [];
        }

        var results = new List<EventLogEntryInfo>();
        foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = TryParseLine(line);
            if (entry is not null)
            {
                results.Add(entry);
            }
        }

        return results.OrderByDescending(e => e.TimeGenerated).Take(maxEntries).ToList();
    }

    private static EventLogEntryInfo? TryParseLine(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;

            // The first line of ndjson output is stream-metadata, not a log event -
            // it has no "eventMessage" field, which is how we recognize and skip it.
            if (!root.TryGetProperty("eventMessage", out var messageProp))
            {
                return null;
            }

            var timestamp = root.TryGetProperty("timestamp", out var tsProp) &&
                             DateTimeOffset.TryParse(tsProp.GetString(), out var ts)
                ? ts
                : DateTimeOffset.MinValue;

            var messageType = root.TryGetProperty("messageType", out var mtProp) ? mtProp.GetString() : null;
            var subsystem = root.TryGetProperty("subsystem", out var subProp) ? subProp.GetString() : null;
            var processPath = root.TryGetProperty("processImagePath", out var procProp) ? procProp.GetString() : null;
            var source = !string.IsNullOrEmpty(processPath)
                ? Path.GetFileName(processPath)
                : (string.IsNullOrEmpty(subsystem) ? "unknown" : subsystem);

            var eventId = root.TryGetProperty("processID", out var pidProp) && pidProp.TryGetInt32(out var pid)
                ? pid
                : 0;

            return new EventLogEntryInfo
            {
                LogName = LogSourceName,
                Source = source,
                Severity = MapSeverity(messageType),
                TimeGenerated = timestamp,
                Message = messageProp.GetString() ?? "(no message)",
                EventId = eventId
            };
        }
        catch (JsonException)
        {
            // Not a JSON log line - skip rather than fail the whole collector.
            return null;
        }
    }

    private static EventLogSeverity MapSeverity(string? messageType) => messageType switch
    {
        "Fault" => EventLogSeverity.Critical,
        "Error" => EventLogSeverity.Error,
        _ => EventLogSeverity.Warning
    };
}
