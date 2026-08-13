using System.ComponentModel;
using DiagClean.Cli.Screens;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class UninstallCommand : Command<UninstallCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("--dry-run")]
        [Description("Preview only - shows what would be removed and exits without removing anything.")]
        public bool DryRunOnly { get; set; }

        [CommandOption("-y|--yes")]
        [Description("Skip the interactive confirmation prompt (for scripted/RMM use). Ignored with --dry-run.")]
        public bool AssumeYes { get; set; }
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Uninstall requires Windows or macOS.[/]");
            return 1;
        }

        var (lister, uninstaller) = Composition.CreateUninstall();
        UninstallScreen.Run(lister, uninstaller, settings.AssumeYes, previewOnly: settings.DryRunOnly);
        return 0;
    }
}
