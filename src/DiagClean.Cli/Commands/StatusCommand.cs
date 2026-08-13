using System.ComponentModel;
using DiagClean.Cli.Screens;
using DiagClean.Core.Status;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class StatusCommand : Command<StatusCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("--once")]
        [Description("Print a single snapshot and exit, instead of the live-refreshing dashboard. Works non-interactively.")]
        public bool Once { get; set; }
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Status requires Windows or macOS.[/]");
            return 1;
        }

        var collector = StatusFactory.Create();
        StatusScreen.Run(collector, settings.Once);
        return 0;
    }
}
