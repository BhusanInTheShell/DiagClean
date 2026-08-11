using System.Diagnostics.Eventing.Reader;
using System.Runtime.Versioning;
using DiagClean.Core.Models;

namespace DiagClean.Core.Diagnostics;

[SupportedOSPlatform("windows")]
public sealed class EventLogCollector : IEventLogCollector
{
    private static readonly string[] LogNames = ["Application", "System"];

    public IReadOnlyList<EventLogEntryInfo> Collect(int maxAgeDays = 7, int maxEntries = 200)
    {
        var results = new List<EventLogEntryInfo>();
        var cutoff = DateTime.UtcNow.AddDays(-maxAgeDays);

        foreach (var logName in LogNames)
        {
            try
            {
                // Level 1=Critical, 2=Error, 3=Warning.
                var queryString =
                    $"*[System[(Level=1 or Level=2 or Level=3) and " +
                    $"TimeCreated[@SystemTime>='{cutoff:yyyy-MM-ddTHH:mm:ss.fffZ}']]]";

                var query = new EventLogQuery(logName, PathType.LogName, queryString) { ReverseDirection = true };
                using var reader = new EventLogReader(query);

                var countForLog = 0;
                while (countForLog < maxEntries && reader.ReadEvent() is { } record)
                {
                    using (record)
                    {
                        results.Add(new EventLogEntryInfo
                        {
                            LogName = logName,
                            Source = record.ProviderName ?? "",
                            Severity = MapLevel(record.Level),
                            TimeGenerated = record.TimeCreated.HasValue
                                ? new DateTimeOffset(record.TimeCreated.Value)
                                : DateTimeOffset.MinValue,
                            Message = SafeFormatDescription(record),
                            EventId = record.Id
                        });
                    }

                    countForLog++;
                }
            }
            catch (EventLogNotFoundException)
            {
                // Log doesn't exist on this system (e.g. stripped-down builds) - skip it.
            }
        }

        return results.OrderByDescending(e => e.TimeGenerated).Take(maxEntries).ToList();
    }

    private static EventLogSeverity MapLevel(byte? level) => level switch
    {
        1 => EventLogSeverity.Critical,
        2 => EventLogSeverity.Error,
        _ => EventLogSeverity.Warning
    };

    private static string SafeFormatDescription(EventRecord record)
    {
        try
        {
            return record.FormatDescription() ?? "(no description)";
        }
        catch (EventLogException)
        {
            // The provider's message-resource DLL isn't registered on this machine - common
            // for third-party drivers/apps. Fall back rather than losing the whole entry.
            return "(description unavailable - provider message file missing)";
        }
    }
}
