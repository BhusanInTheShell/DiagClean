using System.ComponentModel;
using DiagClean.Cli.Screens;
using DiagClean.Core.Models;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class CleanCommand : Command<CleanCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("--preset <PRESET>")]
        [DefaultValue(CleanPreset.Quick)]
        public CleanPreset Preset { get; set; } = CleanPreset.Quick;

        [CommandOption("--dry-run")]
        [Description("Preview only - shows what would be deleted and exits without deleting anything.")]
        public bool DryRunOnly { get; set; }

        [CommandOption("-y|--yes")]
        [Description("Skip the interactive confirmation prompt (for scripted/RMM use). Ignored with --dry-run.")]
        public bool AssumeYes { get; set; }
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Cleaning requires Windows or macOS.[/]");
            return 1;
        }

        var appSettings = AppSettingsModel.Load(AppPaths.SettingsFilePath);
        var categories = appSettings.GetPresetCategories(settings.Preset);
        if (categories.Count == 0)
        {
            categories = settings.Preset == CleanPreset.Deep
                ? Enum.GetValues<CleanCategory>()
                : [CleanCategory.TempFiles, CleanCategory.BrowserCache];
        }

        var targets = Composition.CreateCleanTargets(appSettings);
        CleanScreen.Run(targets, categories, settings.AssumeYes, previewOnly: settings.DryRunOnly);
        return 0;
    }
}
