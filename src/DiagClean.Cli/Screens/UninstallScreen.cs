using DiagClean.Core.Models;
using DiagClean.Core.Uninstall;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class UninstallScreen
{
    // Apps used more recently than this are left unchecked by default in the picker -
    // a nudge toward removing things you've actually stopped using, not something you
    // just installed. Matches mole's Old/Recent convention for its own uninstaller.
    private const int RecentDays = 30;

    public static void Run(IAppLister lister, IAppUninstaller uninstaller, bool assumeYes, bool previewOnly)
    {
        IReadOnlyList<InstalledApp> apps = [];
        AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots)
            .Start("Scanning installed applications...", _ => apps = lister.ListApps());

        if (apps.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No removable applications found.[/]");
            return;
        }

        var ordered = apps.OrderByDescending(a => a.SizeBytes).ToList();
        var cutoff = DateOnly.FromDateTime(DateTime.Now.AddDays(-RecentDays));

        var prompt = new MultiSelectionPrompt<InstalledApp>()
            .Title("Select apps to remove")
            .PageSize(15)
            .InstructionsText("[grey](use space to select, enter to confirm)[/]")
            .UseConverter(app => $"{app.Name} ({FormatUtils.FormatSize(app.SizeBytes)}) | {AgeTag(app, cutoff)}")
            .AddChoices(ordered);

        foreach (var app in ordered.Where(a => AgeTag(a, cutoff) == "Old"))
        {
            prompt.Select(app);
        }

        var selected = AnsiConsole.Prompt(prompt);
        if (selected.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No apps selected.[/]");
            return;
        }

        if (uninstaller.Method == UninstallMethod.VendorUninstaller)
        {
            RunVendorFlow(selected, uninstaller, assumeYes, previewOnly);
        }
        else
        {
            RunDirectFlow(selected, uninstaller, assumeYes, previewOnly);
        }
    }

    /// <summary>macOS: scan leftovers, preview everything (app + leftovers) together,
    /// confirm once, remove everything to Trash in one pass.</summary>
    private static void RunDirectFlow(
        IReadOnlyList<InstalledApp> selected, IAppUninstaller uninstaller, bool assumeYes, bool previewOnly)
    {
        var scanResults = ScanAll(selected, uninstaller);
        PrintSummaryTable(scanResults, includeAppSize: true);

        var grandTotal = scanResults.Sum(r => r.TotalSizeBytes) + selected.Sum(a => a.SizeBytes);
        AnsiConsole.MarkupLine(
            $"\n[bold]{selected.Count}[/] app(s) plus [bold]{scanResults.Sum(r => r.ItemCount)}[/] leftover items, " +
            $"[bold]{FormatUtils.FormatSize(grandTotal)}[/] would be freed (moved to Trash, not permanently deleted).\n");

        if (previewOnly)
        {
            AnsiConsole.MarkupLine("[grey]Dry-run only - nothing was removed.[/]");
            return;
        }

        if (!assumeYes && !Confirm())
        {
            AnsiConsole.MarkupLine("[yellow]Cancelled - nothing was removed.[/]");
            return;
        }

        var outcomes = new List<UninstallOutcome>();
        AnsiConsole.Progress()
            .Columns(new TaskDescriptionColumn(), new ProgressBarColumn(), new PercentageColumn(), new SpinnerColumn())
            .Start(ctx =>
            {
                foreach (var result in scanResults)
                {
                    var task = ctx.AddTask(result.App.Name, maxValue: 1);
                    outcomes.Add(uninstaller.RemoveDirectly(result.App, result.Items));
                    task.Value = 1;
                }
            });

        PrintOutcomeSummary(outcomes);
        UninstallRunLogger.Log(outcomes);
    }

    /// <summary>Windows: each app's own uninstaller runs first (interactive, one at a
    /// time), then leftover residue is scanned and cleaned as a separate step.</summary>
    private static void RunVendorFlow(
        IReadOnlyList<InstalledApp> selected, IAppUninstaller uninstaller, bool assumeYes, bool previewOnly)
    {
        if (previewOnly)
        {
            AnsiConsole.MarkupLine(
                "[grey]Dry-run isn't meaningful for vendor uninstallers (nothing happens until you launch one) - " +
                "showing the selected apps only.[/]");
            var table = new Table().Border(TableBorder.Rounded);
            table.AddColumn("App");
            table.AddColumn(new TableColumn("Size").RightAligned());
            foreach (var app in selected)
            {
                table.AddRow(Markup.Escape(app.Name), FormatUtils.FormatSize(app.SizeBytes));
            }

            AnsiConsole.Write(table);
            return;
        }

        if (!assumeYes && !AnsiConsole.Confirm(
                $"This launches each app's own uninstaller ({selected.Count} app(s)), one at a time. Continue?"))
        {
            AnsiConsole.MarkupLine("[yellow]Cancelled.[/]");
            return;
        }

        var removedApps = new List<InstalledApp>();
        foreach (var app in selected)
        {
            AnsiConsole.MarkupLine($"\n[bold]Launching uninstaller for {Markup.Escape(app.Name)}...[/]");
            var succeeded = uninstaller.RunVendorUninstaller(app);
            AnsiConsole.MarkupLine(succeeded
                ? $"[green]{Markup.Escape(app.Name)} uninstaller finished.[/]"
                : $"[yellow]{Markup.Escape(app.Name)} uninstaller reported a non-zero exit or couldn't be launched - " +
                  "it may not be fully removed.[/]");
            removedApps.Add(app);
        }

        AnsiConsole.MarkupLine("\n[bold]Scanning for leftover files...[/]");
        var scanResults = ScanAll(removedApps, uninstaller);
        PrintSummaryTable(scanResults, includeAppSize: false);

        if (scanResults.Sum(r => r.ItemCount) == 0)
        {
            AnsiConsole.MarkupLine("[green]No leftover files found.[/]");
            return;
        }

        var totalBytes = scanResults.Sum(r => r.TotalSizeBytes);
        AnsiConsole.MarkupLine(
            $"\n[bold]{scanResults.Sum(r => r.ItemCount)}[/] leftover items, [bold]{FormatUtils.FormatSize(totalBytes)}[/] would be freed.\n");

        if (!assumeYes && !Confirm())
        {
            AnsiConsole.MarkupLine("[yellow]Cancelled - leftover files were not removed.[/]");
            return;
        }

        var outcomes = scanResults.Select(r => uninstaller.RemoveDirectly(r.App, r.Items)).ToList();
        PrintOutcomeSummary(outcomes);
        UninstallRunLogger.Log(outcomes);
    }

    private static List<AppLeftoverScanResult> ScanAll(IReadOnlyList<InstalledApp> apps, IAppUninstaller uninstaller)
    {
        var results = new List<AppLeftoverScanResult>();
        AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots)
            .Start("Scanning for leftover files...", ctx =>
            {
                foreach (var app in apps)
                {
                    ctx.Status($"Scanning {app.Name}...");
                    results.Add(uninstaller.ScanLeftovers(app));
                }
            });

        return results;
    }

    private static void PrintSummaryTable(List<AppLeftoverScanResult> scanResults, bool includeAppSize)
    {
        var table = new Table().Border(TableBorder.Rounded).Title("Preview - nothing has been removed yet");
        table.AddColumn("App");
        table.AddColumn(new TableColumn("Leftover Items").RightAligned());
        table.AddColumn(new TableColumn("Leftover Size").RightAligned());
        if (includeAppSize)
        {
            table.AddColumn(new TableColumn("App Size").RightAligned());
        }

        foreach (var result in scanResults)
        {
            var row = new List<string>
            {
                Markup.Escape(result.App.Name),
                result.ItemCount.ToString(),
                FormatUtils.FormatSize(result.TotalSizeBytes)
            };
            if (includeAppSize)
            {
                row.Add(FormatUtils.FormatSize(result.App.SizeBytes));
            }

            table.AddRow(row.ToArray());
        }

        AnsiConsole.Write(table);
    }

    private static bool Confirm()
    {
        var response = AnsiConsole.Prompt(
            new TextPrompt<string>(
                "Type [bold red]DELETE[/] to remove these apps/files, or press Enter to cancel:")
                .AllowEmpty());

        return string.Equals(response, "DELETE", StringComparison.Ordinal);
    }

    private static void PrintOutcomeSummary(List<UninstallOutcome> outcomes)
    {
        var totalFreed = outcomes.Sum(o => o.BytesFreed);
        var appsRemoved = outcomes.Count(o => o.AppRemoved);
        var itemsRemoved = outcomes.Sum(o => o.LeftoverItemsRemoved);
        var totalFailed = outcomes.Sum(o => o.Failures.Count);

        AnsiConsole.MarkupLine(
            $"\n[green bold]Done.[/] {appsRemoved} app(s) removed, {itemsRemoved} leftover item(s) removed, " +
            $"[bold]{FormatUtils.FormatSize(totalFreed)}[/] freed.");

        if (totalFailed > 0)
        {
            AnsiConsole.MarkupLine($"[yellow]{totalFailed} item(s) could not be removed (locked or in use):[/]");
            foreach (var failure in outcomes.SelectMany(o => o.Failures).Take(10))
            {
                AnsiConsole.MarkupLine($"  [yellow]-[/] {Markup.Escape(failure.FullPath)}: {Markup.Escape(failure.Reason)}");
            }
        }
    }

    private static string AgeTag(InstalledApp app, DateOnly cutoff) =>
        app.LastModified is { } lastModified && lastModified >= cutoff ? "Recent" : "Old";
}
