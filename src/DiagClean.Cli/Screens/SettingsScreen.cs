using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class SettingsScreen
{
    public static void Show(AppSettingsModel settings)
    {
        AnsiConsole.MarkupLine($"[bold]Config file:[/] {Markup.Escape(AppPaths.SettingsFilePath)}");
        AnsiConsole.MarkupLine($"[bold]Reports directory:[/] {Markup.Escape(AppPaths.ReportsDirectory)}");
        AnsiConsole.MarkupLine($"[bold]Logs directory:[/] {Markup.Escape(AppPaths.LogsDirectory)}");

        AnsiConsole.MarkupLine("\n[bold]User-configured protected paths[/] (in addition to the built-in ones):");
        if (settings.ProtectedPaths.Count == 0)
        {
            AnsiConsole.MarkupLine("  [grey](none - edit protectedPaths in the config file above to add some)[/]");
        }
        else
        {
            foreach (var path in settings.ProtectedPaths)
            {
                AnsiConsole.MarkupLine($"  - {Markup.Escape(path)}");
            }
        }

        AnsiConsole.MarkupLine("\n[bold]Clean presets:[/]");
        foreach (var (preset, categories) in settings.Presets)
        {
            AnsiConsole.MarkupLine($"  {Markup.Escape(preset)}: {Markup.Escape(string.Join(", ", categories))}");
        }

        AnsiConsole.WriteLine();
        AnsiConsole.Prompt(new TextPrompt<string>("Press Enter to return to the main menu").AllowEmpty());
    }
}
