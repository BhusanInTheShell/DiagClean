using DiagClean.Core.Models;
using DiagClean.Core.Reporting;
using QuestPDF.Infrastructure;
using Xunit;

namespace DiagClean.Tests.Reporting;

public class PdfReportBuilderTests
{
    static PdfReportBuilderTests()
    {
        // QuestPDF refuses to render without a license selection at runtime - this
        // confirms the Community license path actually works, not just that the
        // fluent API compiles.
        QuestPDF.Settings.License = LicenseType.Community;
    }

    [Fact]
    public void Builds_a_non_empty_pdf_for_a_full_report()
    {
        var report = new DiagnosticReport
        {
            MachineName = "TEST-PC01",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech1",
            Hardware = new HardwareInfo { CpuName = "Test CPU", CpuCores = 4, CpuLogicalProcessors = 8, TotalRamGb = 16 },
            Disks =
            [
                new DiskInfo { DeviceId = @"\\.\PHYSICALDRIVE0", Model = "Test SSD", SizeGb = 512, FreeGb = 200, SmartStatus = SmartStatus.Healthy }
            ],
            Performance = new PerformanceSnapshot { CpuLoadPercent = 12.5, MemoryUsedPercent = 40, SystemUptimeHours = 5 },
            NetworkAdapters =
            [
                new NetworkAdapterInfo { Name = "Ethernet", IsUp = true, IpAddresses = ["192.168.1.10"] }
            ],
            EventLogEntries =
            [
                new EventLogEntryInfo
                {
                    LogName = "Application", Source = "Test", Severity = EventLogSeverity.Error,
                    TimeGenerated = DateTimeOffset.Now, Message = "Something went wrong", EventId = 1000
                }
            ],
            InstalledSoftware = [new InstalledSoftware { Name = "Test App", Version = "1.0", Publisher = "Acme" }]
        };

        var bytes = PdfReportBuilder.Build(report);

        Assert.NotEmpty(bytes);
        // %PDF- is the standard PDF file signature.
        Assert.Equal("%PDF-"u8.ToArray(), bytes[..5]);
    }

    [Fact]
    public void Builds_without_throwing_when_the_report_is_mostly_empty()
    {
        var report = new DiagnosticReport
        {
            MachineName = "PC",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech",
        };

        var bytes = PdfReportBuilder.Build(report);

        Assert.NotEmpty(bytes);
    }

    [Fact]
    public void Truncates_event_log_rows_beyond_the_cap_without_throwing()
    {
        var manyEntries = Enumerable.Range(0, 200)
            .Select(i => new EventLogEntryInfo
            {
                LogName = "Application",
                Source = "Test",
                Severity = EventLogSeverity.Warning,
                TimeGenerated = DateTimeOffset.Now.AddMinutes(-i),
                Message = $"Entry {i}",
                EventId = i
            })
            .ToList();

        var report = new DiagnosticReport
        {
            MachineName = "PC",
            GeneratedAt = DateTimeOffset.Now,
            CollectedBy = "tech",
            EventLogEntries = manyEntries
        };

        var bytes = PdfReportBuilder.Build(report);

        Assert.NotEmpty(bytes);
    }
}
