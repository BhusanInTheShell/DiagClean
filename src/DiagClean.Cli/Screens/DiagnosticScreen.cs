using DiagClean.Core.Diagnostics;
using DiagClean.Core.Reporting;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class DiagnosticScreen
{
    public static string Run(DiagnosticCollectorService service, string? outputPathOverride)
    {
        Core.Models.DiagnosticReport? report = null;

        AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots)
            .SpinnerStyle(Style.Parse("blue"))
            .Start("Collecting hardware, disk, network, event log, and software data...", _ =>
            {
                report = service.Collect(Environment.UserName);
            });

        var html = HtmlReportBuilder.Build(report!);

        var outputPath = outputPathOverride ?? Path.Combine(
            AppPaths.ReportsDirectory,
            $"DiagClean-Report-{Sanitize(report!.MachineName)}-{report.GeneratedAt:yyyyMMdd-HHmmss}.html");

        var directory = Path.GetDirectoryName(Path.GetFullPath(outputPath));
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(outputPath, html);

        AnsiConsole.MarkupLine($"[green]Report written to[/] [underline]{Markup.Escape(outputPath)}[/]");

        if (report!.CollectorErrors.Count > 0)
        {
            AnsiConsole.MarkupLine(
                $"[yellow]Note: {report.CollectorErrors.Count} collector(s) reported issues - the report may be incomplete:[/]");
            foreach (var err in report.CollectorErrors)
            {
                AnsiConsole.MarkupLine($"  [yellow]-[/] {Markup.Escape(err.CollectorName)}: {Markup.Escape(err.Message)}");
            }
        }

        return outputPath;
    }

    private static string Sanitize(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return new string(name.Select(c => invalid.Contains(c) ? '_' : c).ToArray());
    }
}
