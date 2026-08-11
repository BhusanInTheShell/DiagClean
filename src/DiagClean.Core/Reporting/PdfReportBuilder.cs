using DiagClean.Core.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace DiagClean.Core.Reporting;

/// <summary>
/// Renders a <see cref="DiagnosticReport"/> as a PDF using QuestPDF - a pure .NET
/// library with no external process dependency (no headless browser, no wkhtmltopdf
/// binary to ship), which matters for a tool whose whole pitch is a single portable
/// executable. The caller must set QuestPDF.Settings.License once at startup (see
/// DiagClean.Cli.Program) - Core deliberately has no startup side effects of its own.
///
/// Event log entries are capped to keep the PDF a reasonable length for printing/emailing;
/// the full list is still available in the HTML report.
/// </summary>
public static class PdfReportBuilder
{
    private const int MaxEventLogRows = 60;

    public static byte[] Build(DiagnosticReport report)
    {
        var document = Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(1.5f, Unit.Centimetre);
                page.DefaultTextStyle(x => x.FontSize(9));

                page.Header().Element(c => ComposeHeader(c, report));
                page.Content().Element(c => ComposeContent(c, report));
                page.Footer().AlignCenter().Text(text =>
                {
                    text.Span("DiagClean  ·  Page ");
                    text.CurrentPageNumber();
                    text.Span(" of ");
                    text.TotalPages();
                });
            });
        });

        return document.GeneratePdf();
    }

    private static void ComposeHeader(IContainer container, DiagnosticReport report)
    {
        container.Column(col =>
        {
            col.Item().Text("DiagClean Diagnostic Report").FontSize(18).Bold();
            col.Item().PaddingTop(2).Text(
                $"Machine: {report.MachineName}    Generated: {report.GeneratedAt:f}    Collected by: {report.CollectedBy}")
                .FontSize(8).FontColor(Colors.Grey.Darken2);
            col.Item().PaddingTop(6).PaddingBottom(6).LineHorizontal(1).LineColor(Colors.Grey.Lighten2);
        });
    }

    private static void ComposeContent(IContainer container, DiagnosticReport report)
    {
        container.Column(col =>
        {
            col.Spacing(12);

            if (report.CollectorErrors.Count > 0)
            {
                col.Item().Element(c => CollectorErrorsSection(c, report.CollectorErrors));
            }

            col.Item().Element(c => HardwareSection(c, report.Hardware));
            col.Item().Element(c => DisksSection(c, report.Disks));
            col.Item().Element(c => PerformanceSection(c, report.Performance));
            col.Item().Element(c => NetworkSection(c, report.NetworkAdapters));
            col.Item().Element(c => EventLogSection(c, report.EventLogEntries));
            col.Item().Element(c => SoftwareSection(c, report.InstalledSoftware));
        });
    }

    private static void SectionTitle(ColumnDescriptor col, string title)
    {
        col.Item().Text(title.ToUpperInvariant()).FontSize(10).Bold().FontColor(Colors.Grey.Darken2);
        col.Item().PaddingBottom(2).LineHorizontal(0.5f).LineColor(Colors.Grey.Lighten3);
    }

    private static void HardwareSection(IContainer container, HardwareInfo? hw)
    {
        container.Column(col =>
        {
            SectionTitle(col, "Hardware Summary");

            if (hw is null)
            {
                col.Item().Text("Hardware data unavailable.").Italic().FontColor(Colors.Grey.Medium);
                return;
            }

            col.Item().Text($"CPU: {hw.CpuName}");
            col.Item().Text($"Cores / Logical Processors: {hw.CpuCores} / {hw.CpuLogicalProcessors}");
            col.Item().Text($"RAM: {hw.TotalRamGb:0.#} GB");
            col.Item().Text($"Motherboard: {hw.MotherboardManufacturer} {hw.MotherboardModel}".Trim());
            col.Item().Text($"BIOS Version: {hw.BiosVersion}");
            col.Item().Text($"GPU: {(hw.GpuNames.Count > 0 ? string.Join(", ", hw.GpuNames) : "-")}");
        });
    }

    private static void DisksSection(IContainer container, IReadOnlyList<DiskInfo> disks)
    {
        container.Column(col =>
        {
            SectionTitle(col, "Disk Health");

            if (disks.Count == 0)
            {
                col.Item().Text("No disk data collected.").Italic().FontColor(Colors.Grey.Medium);
                return;
            }

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(3);
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(2);
                });

                table.Header(header =>
                {
                    HeaderCell(header, "Device");
                    HeaderCell(header, "Model");
                    HeaderCell(header, "Type");
                    HeaderCell(header, "Size");
                    HeaderCell(header, "Free");
                    HeaderCell(header, "SMART");
                });

                foreach (var d in disks)
                {
                    BodyCell(table, d.DeviceId);
                    BodyCell(table, d.Model);
                    BodyCell(table, d.MediaType);
                    BodyCell(table, $"{d.SizeGb:0.#} GB");
                    BodyCell(table, $"{d.FreeGb:0.#} GB");
                    BodyCell(table, d.SmartStatus.ToString());
                }
            });
        });
    }

    private static void PerformanceSection(IContainer container, PerformanceSnapshot? perf)
    {
        container.Column(col =>
        {
            SectionTitle(col, "Performance Snapshot");

            if (perf is null)
            {
                col.Item().Text("Performance data unavailable.").Italic().FontColor(Colors.Grey.Medium);
                return;
            }

            col.Item().Text($"CPU Load: {perf.CpuLoadPercent:0.#}%");
            col.Item().Text($"Memory Used: {perf.MemoryUsedPercent:0.#}%");
            col.Item().Text($"System Uptime: {perf.SystemUptimeHours:0.#} hours");
            col.Item().Text($"Recent App Crashes (24h): {perf.RecentApplicationCrashCount}");
        });
    }

    private static void NetworkSection(IContainer container, IReadOnlyList<NetworkAdapterInfo> adapters)
    {
        container.Column(col =>
        {
            SectionTitle(col, "Network Configuration");

            if (adapters.Count == 0)
            {
                col.Item().Text("No network adapters found.").Italic().FontColor(Colors.Grey.Medium);
                return;
            }

            foreach (var a in adapters)
            {
                col.Item().PaddingTop(4).Text($"{a.Name} ({(a.IsUp ? "Up" : "Down")})").Bold();
                col.Item().Text($"  {a.Description}").FontColor(Colors.Grey.Darken1);
                col.Item().Text($"  MAC: {a.MacAddress}    IP: {(a.IpAddresses.Count > 0 ? string.Join(", ", a.IpAddresses) : "-")}");
                col.Item().Text($"  DNS: {(a.DnsServers.Count > 0 ? string.Join(", ", a.DnsServers) : "-")}    Gateway: {a.Gateway ?? "-"}");
            }
        });
    }

    private static void EventLogSection(IContainer container, IReadOnlyList<EventLogEntryInfo> entries)
    {
        container.Column(col =>
        {
            SectionTitle(col, $"Recent Event Log Errors & Warnings ({entries.Count})");

            if (entries.Count == 0)
            {
                col.Item().Text("No recent errors or warnings found.").Italic().FontColor(Colors.Grey.Medium);
                return;
            }

            var shown = entries.OrderByDescending(e => e.TimeGenerated).Take(MaxEventLogRows).ToList();

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(1);
                    columns.RelativeColumn(5);
                });

                table.Header(header =>
                {
                    HeaderCell(header, "Time");
                    HeaderCell(header, "Log");
                    HeaderCell(header, "Source");
                    HeaderCell(header, "Sev.");
                    HeaderCell(header, "Message");
                });

                foreach (var e in shown)
                {
                    BodyCell(table, e.TimeGenerated.ToString("g"));
                    BodyCell(table, e.LogName);
                    BodyCell(table, e.Source);
                    BodyCell(table, e.Severity.ToString());
                    BodyCell(table, Truncate(e.Message, 180));
                }
            });

            if (entries.Count > MaxEventLogRows)
            {
                col.Item().PaddingTop(4)
                    .Text($"...and {entries.Count - MaxEventLogRows} more. See the HTML report for the full list.")
                    .Italic().FontColor(Colors.Grey.Medium);
            }
        });
    }

    private static void SoftwareSection(IContainer container, IReadOnlyList<InstalledSoftware> software)
    {
        container.Column(col =>
        {
            SectionTitle(col, $"Installed Software ({software.Count})");

            if (software.Count == 0)
            {
                col.Item().Text("No installed software data collected.").Italic().FontColor(Colors.Grey.Medium);
                return;
            }

            col.Item().Table(table =>
            {
                table.ColumnsDefinition(columns =>
                {
                    columns.RelativeColumn(4);
                    columns.RelativeColumn(2);
                    columns.RelativeColumn(3);
                    columns.RelativeColumn(2);
                });

                table.Header(header =>
                {
                    HeaderCell(header, "Name");
                    HeaderCell(header, "Version");
                    HeaderCell(header, "Publisher");
                    HeaderCell(header, "Installed");
                });

                foreach (var s in software.OrderBy(s => s.Name, StringComparer.OrdinalIgnoreCase))
                {
                    BodyCell(table, s.Name);
                    BodyCell(table, s.Version);
                    BodyCell(table, s.Publisher);
                    BodyCell(table, s.InstallDate?.ToString("yyyy-MM-dd") ?? "-");
                }
            });
        });
    }

    private static void CollectorErrorsSection(IContainer container, IReadOnlyList<CollectorError> errors)
    {
        container.Column(col =>
        {
            col.Item().Background(Colors.Yellow.Lighten4).Padding(6).Column(inner =>
            {
                inner.Item().Text("This report may be incomplete").Bold().FontColor(Colors.Orange.Darken2);
                foreach (var e in errors)
                {
                    inner.Item().Text($"{e.CollectorName}: {e.Message}").FontSize(8);
                }
            });
        });
    }

    private static void HeaderCell(TableCellDescriptor header, string text) =>
        header.Cell().BorderBottom(1).BorderColor(Colors.Grey.Darken1).PaddingBottom(2)
            .Text(text).Bold().FontSize(8).FontColor(Colors.Grey.Darken2);

    private static void BodyCell(TableDescriptor table, string text) =>
        table.Cell().BorderBottom(0.5f).BorderColor(Colors.Grey.Lighten3).PaddingVertical(2)
            .Text(text ?? "-").FontSize(8);

    private static string Truncate(string text, int maxLength) =>
        text.Length <= maxLength ? text : text[..maxLength] + "...";
}
