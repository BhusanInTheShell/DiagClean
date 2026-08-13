using System.ComponentModel;
using DiagClean.Cli.Screens;
using DiagClean.Core.Reporting;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class DiagCommand : Command<DiagCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("-o|--output <PATH>")]
        [Description("Output file path. Extension is ignored/replaced based on --format.")]
        public string? Output { get; set; }

        [CommandOption("-f|--format <FORMAT>")]
        [DefaultValue(ReportFormat.Html)]
        public ReportFormat Format { get; set; } = ReportFormat.Html;
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Diagnostics require Windows or macOS.[/]");
            return 1;
        }

        AppPaths.EnsureDataDirectories();
        var service = Composition.CreateDiagnosticService();
        DiagnosticScreen.Run(service, settings.Format, settings.Output);
        return 0;
    }
}
