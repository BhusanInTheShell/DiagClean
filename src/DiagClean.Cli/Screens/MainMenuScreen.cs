using DiagClean.Core.Models;
using DiagClean.Core.Reporting;
using DiagClean.Core.Uninstall;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class MainMenuScreen
{
    private const string RunDiagnostic = "Run Full Diagnostic Report";
    private const string QuickClean = "Quick Clean (temp + browser cache)";
    private const string DeepCleanWindows = "Deep Clean (+ Windows Update + installer leftovers)";
    private const string DeepCleanMac = "Deep Clean (+ system caches)";
    private const string CustomClean = "Custom Clean (choose categories)";
    private const string Uninstall = "Uninstall (remove apps + leftovers)";
    private const string Settings = "Settings";
    private const string Exit = "Exit";

    public static void Run()
    {
        PrintBanner();
        var deepCleanLabel = OperatingSystem.IsWindows() ? DeepCleanWindows : DeepCleanMac;

        while (true)
        {
            AnsiConsole.WriteLine();
            var choice = AnsiConsole.Prompt(
                new SelectionPrompt<string>()
                    .Title("What would you like to do?")
                    .AddChoices(RunDiagnostic, QuickClean, deepCleanLabel, CustomClean, Uninstall, Settings, Exit));

            AnsiConsole.WriteLine();

            switch (choice)
            {
                case RunDiagnostic:
                    RunDiagnosticFlow();
                    break;
                case QuickClean:
                    RunCleanFlow(CleanPreset.Quick);
                    break;
                case DeepCleanWindows:
                case DeepCleanMac:
                    RunCleanFlow(CleanPreset.Deep);
                    break;
                case CustomClean:
                    RunCustomCleanFlow();
                    break;
                case Uninstall:
                    RunUninstallFlow();
                    break;
                case Settings:
                    SettingsScreen.Show(AppSettingsModel.Load(AppPaths.SettingsFilePath));
                    break;
                case Exit:
                    return;
            }
        }
    }

    private static void PrintBanner()
    {
        AnsiConsole.Write(new FigletText("DiagClean").Color(Color.SteelBlue));
        var elevated = ElevationHelper.IsRunningAsAdministrator();
        var privilegedRoleName = OperatingSystem.IsWindows() ? "Administrator" : "root";
        var elevatedText = elevated ? $"[green]{privilegedRoleName}[/]" : "[yellow]Standard user[/]";
        AnsiConsole.MarkupLine($"Diagnostic collector + safe cleanup for helpdesk technicians   [grey]|[/]   Running as: {elevatedText}");

        if (!elevated)
        {
            AnsiConsole.MarkupLine(
                $"[grey]Some diagnostics (SMART, some event logs) and Deep Clean need {privilegedRoleName} to see everything.[/]");
        }
    }

    private static void RunDiagnosticFlow()
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Diagnostics require Windows or macOS.[/]");
            return;
        }

        var format = AnsiConsole.Prompt(
            new SelectionPrompt<ReportFormat>()
                .Title("Report format?")
                .AddChoices(ReportFormat.Html, ReportFormat.Pdf, ReportFormat.Both));

        AppPaths.EnsureDataDirectories();
        var service = Composition.CreateDiagnosticService();
        var paths = DiagnosticScreen.Run(service, format, outputPathOverride: null);

        if (paths.Count > 0 && AnsiConsole.Confirm("Open the report now?"))
        {
            TryOpen(paths[0]);
        }
    }

    private static void RunCleanFlow(CleanPreset preset)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Cleaning requires Windows or macOS.[/]");
            return;
        }

        var settings = AppSettingsModel.Load(AppPaths.SettingsFilePath);
        var categories = settings.GetPresetCategories(preset);
        if (categories.Count == 0)
        {
            categories = preset == CleanPreset.Deep
                ? Enum.GetValues<CleanCategory>()
                : [CleanCategory.TempFiles, CleanCategory.BrowserCache];
        }

        var targets = Composition.CreateCleanTargets(settings);
        CleanScreen.Run(targets, categories, assumeYes: false);
    }

    private static void RunCustomCleanFlow()
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Cleaning requires Windows or macOS.[/]");
            return;
        }

        var selected = AnsiConsole.Prompt(
            new MultiSelectionPrompt<CleanCategory>()
                .Title("Select categories to clean")
                .InstructionsText("[grey](use space to select, enter to confirm)[/]")
                .AddChoices(Enum.GetValues<CleanCategory>()));

        if (selected.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No categories selected.[/]");
            return;
        }

        var settings = AppSettingsModel.Load(AppPaths.SettingsFilePath);
        var targets = Composition.CreateCleanTargets(settings);
        CleanScreen.Run(targets, selected, assumeYes: false);
    }

    private static void RunUninstallFlow()
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Uninstall requires Windows or macOS.[/]");
            return;
        }

        var (lister, uninstaller) = Composition.CreateUninstall();
        UninstallScreen.Run(lister, uninstaller, assumeYes: false, previewOnly: false);
    }

    private static void TryOpen(string path)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            AnsiConsole.MarkupLine($"[yellow]Couldn't open the report automatically: {Markup.Escape(ex.Message)}[/]");
        }
    }
}
