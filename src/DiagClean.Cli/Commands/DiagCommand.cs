using DiagClean.Cli.Screens;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class DiagCommand : Command<DiagCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("-o|--output <PATH>")]
        public string? Output { get; set; }
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows())
        {
            AnsiConsole.MarkupLine("[red]Diagnostics require Windows.[/]");
            return 1;
        }

        AppPaths.EnsureDataDirectories();
        var service = Composition.CreateDiagnosticService();
        DiagnosticScreen.Run(service, settings.Output);
        return 0;
    }
}
