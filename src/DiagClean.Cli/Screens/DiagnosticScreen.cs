using DiagClean.Core.Diagnostics;
using DiagClean.Core.Reporting;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class DiagnosticScreen
{
    /// <returns>The report file(s) written - one path for Html/Pdf, two for Both.</returns>
    public static IReadOnlyList<string> Run(
        DiagnosticCollectorService service, ReportFormat format, string? outputPathOverride)
    {
        Core.Models.DiagnosticReport? report = null;

        AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots)
            .SpinnerStyle(Style.Parse("blue"))
            .Start("Collecting hardware, disk, network, event log, and software data...", _ =>
            {
                report = service.Collect(Environment.UserName);
            });

        var basePath = outputPathOverride is null
            ? Path.Combine(
                AppPaths.ReportsDirectory,
                $"DiagClean-Report-{Sanitize(report!.MachineName)}-{report.GeneratedAt:yyyyMMdd-HHmmss}")
            : Path.Combine(
                Path.GetDirectoryName(Path.GetFullPath(outputPathOverride)) ?? ".",
                Path.GetFileNameWithoutExtension(outputPathOverride));

        var directory = Path.GetDirectoryName(Path.GetFullPath(basePath));
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var written = new List<string>();

        if (format is ReportFormat.Html or ReportFormat.Both)
        {
            var htmlPath = basePath + ".html";
            File.WriteAllText(htmlPath, HtmlReportBuilder.Build(report!));
            written.Add(htmlPath);
        }

        if (format is ReportFormat.Pdf or ReportFormat.Both)
        {
            var pdfPath = basePath + ".pdf";
            File.WriteAllBytes(pdfPath, PdfReportBuilder.Build(report!));
            written.Add(pdfPath);
        }

        foreach (var path in written)
        {
            AnsiConsole.MarkupLine($"[green]Report written to[/] [underline]{Markup.Escape(path)}[/]");
        }

        if (report!.CollectorErrors.Count > 0)
        {
            AnsiConsole.MarkupLine(
                $"[yellow]Note: {report.CollectorErrors.Count} collector(s) reported issues - the report may be incomplete:[/]");
            foreach (var err in report.CollectorErrors)
            {
                AnsiConsole.MarkupLine($"  [yellow]-[/] {Markup.Escape(err.CollectorName)}: {Markup.Escape(err.Message)}");
            }
        }

        return written;
    }

    private static string Sanitize(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return new string(name.Select(c => invalid.Contains(c) ? '_' : c).ToArray());
    }
}
