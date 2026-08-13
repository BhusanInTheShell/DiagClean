using System.ComponentModel;
using DiagClean.Cli.Screens;
using DiagClean.Core.Optimize;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class OptimizeCommand : Command<OptimizeCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("--dry-run")]
        [Description("Preview only - shows what would run and exits without running anything.")]
        public bool DryRunOnly { get; set; }

        [CommandOption("-y|--yes")]
        [Description("Skip the interactive confirmation prompt (for scripted/RMM use). Ignored with --dry-run.")]
        public bool AssumeYes { get; set; }
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Optimize requires Windows or macOS.[/]");
            return 1;
        }

        var actions = OptimizeFactory.Create();
        OptimizeScreen.Run(actions, settings.AssumeYes, previewOnly: settings.DryRunOnly);
        return 0;
    }
}
