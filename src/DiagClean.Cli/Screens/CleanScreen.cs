using DiagClean.Core.Cleaning;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class CleanScreen
{
    /// <summary>
    /// Always scans and previews first. Deletion only happens if <paramref name="assumeYes"/>
    /// is true (explicit scripted opt-in, e.g. `--yes`) or the technician types the
    /// confirmation phrase interactively. There is no code path that deletes without one
    /// of those two explicit signals.
    /// </summary>
    public static void Run(
        IReadOnlyList<ICleanTarget> allTargets,
        IReadOnlyList<CleanCategory> categoriesToInclude,
        bool assumeYes,
        bool previewOnly = false)
    {
        var targets = allTargets.Where(t => categoriesToInclude.Contains(t.Category)).ToList();
        if (targets.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No categories selected.[/]");
            return;
        }

        var scanResults = Scan(targets);

        var grandTotalBytes = scanResults.Sum(r => r.TotalSizeBytes);
        var grandTotalItems = scanResults.Sum(r => r.ItemCount);

        PrintSummaryTable(scanResults);

        if (grandTotalItems == 0)
        {
            AnsiConsole.MarkupLine("[green]Nothing to clean - all target locations are already empty.[/]");
            return;
        }

        PrintSampleItems(scanResults);

        AnsiConsole.MarkupLine(
            $"\n[bold]{grandTotalItems}[/] items, [bold]{FormatUtils.FormatSize(grandTotalBytes)}[/] would be freed.\n");

        if (previewOnly)
        {
            AnsiConsole.MarkupLine("[grey]Dry-run only - nothing was deleted.[/]");
            return;
        }

        if (!assumeYes && !Confirm())
        {
            AnsiConsole.MarkupLine("[yellow]Cancelled - nothing was deleted.[/]");
            return;
        }

        var outcomes = Execute(targets, scanResults);
        PrintOutcomeSummary(outcomes);
        CleanRunLogger.Log(outcomes);
    }

    private static List<ScanResult> Scan(List<ICleanTarget> targets)
    {
        var scanResults = new List<ScanResult>();

        AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots)
            .Start("Scanning...", ctx =>
            {
                foreach (var target in targets)
                {
                    ctx.Status($"Scanning {target.DisplayName}...");
                    scanResults.Add(target.Scan());
                }
            });

        return scanResults;
    }

    private static void PrintSummaryTable(List<ScanResult> scanResults)
    {
        var table = new Table().Border(TableBorder.Rounded).Title("Dry-run preview - nothing has been deleted yet");
        table.AddColumn("Category");
        table.AddColumn(new TableColumn("Items").RightAligned());
        table.AddColumn(new TableColumn("Size").RightAligned());
        table.AddColumn(new TableColumn("Skipped (protected)").RightAligned());

        foreach (var result in scanResults)
        {
            table.AddRow(
                result.Category.ToString(),
                result.ItemCount.ToString(),
                FormatUtils.FormatSize(result.TotalSizeBytes),
                result.SkippedProtectedPaths.Count.ToString());
        }

        AnsiConsole.Write(table);
    }

    private static void PrintSampleItems(List<ScanResult> scanResults)
    {
        var sample = scanResults
            .SelectMany(r => r.Items)
            .OrderByDescending(i => i.SizeBytes)
            .Take(15)
            .ToList();

        if (sample.Count == 0)
        {
            return;
        }

        AnsiConsole.MarkupLine("\n[bold]Largest items that will be deleted:[/]");
        var table = new Table().Border(TableBorder.Simple);
        table.AddColumn("Path");
        table.AddColumn(new TableColumn("Size").RightAligned());

        foreach (var item in sample)
        {
            table.AddRow(Markup.Escape(item.FullPath), FormatUtils.FormatSize(item.SizeBytes));
        }

        AnsiConsole.Write(table);
    }

    private static bool Confirm()
    {
        var response = AnsiConsole.Prompt(
            new TextPrompt<string>(
                "Type [bold red]DELETE[/] to permanently remove these files, or press Enter to cancel:")
                .AllowEmpty());

        return string.Equals(response, "DELETE", StringComparison.Ordinal);
    }

    private static List<CleanOutcome> Execute(List<ICleanTarget> targets, List<ScanResult> scanResults)
    {
        var engine = new DryRunEngine(new System.IO.Abstractions.FileSystem());
        var outcomes = new List<CleanOutcome>();

        AnsiConsole.Progress()
            .Columns(new TaskDescriptionColumn(), new ProgressBarColumn(), new PercentageColumn(), new SpinnerColumn())
            .Start(ctx =>
            {
                foreach (var (target, result) in targets.Zip(scanResults))
                {
                    var task = ctx.AddTask(target.DisplayName, maxValue: Math.Max(result.ItemCount, 1));
                    var progress = new Progress<CleanItem>(_ => task.Increment(1));

                    var outcome = engine.Execute(result, target.Guard, progress);
                    outcomes.Add(outcome);

                    task.Value = task.MaxValue;
                }
            });

        return outcomes;
    }

    private static void PrintOutcomeSummary(List<CleanOutcome> outcomes)
    {
        var totalFreed = outcomes.Sum(o => o.BytesFreed);
        var totalDeleted = outcomes.Sum(o => o.ItemsDeleted);
        var totalFailed = outcomes.Sum(o => o.Failures.Count);

        AnsiConsole.MarkupLine(
            $"\n[green bold]Done.[/] {totalDeleted} items deleted, [bold]{FormatUtils.FormatSize(totalFreed)}[/] freed.");

        if (totalFailed > 0)
        {
            AnsiConsole.MarkupLine($"[yellow]{totalFailed} item(s) could not be deleted (locked or in use):[/]");
            foreach (var failure in outcomes.SelectMany(o => o.Failures).Take(10))
            {
                AnsiConsole.MarkupLine($"  [yellow]-[/] {Markup.Escape(failure.FullPath)}: {Markup.Escape(failure.Reason)}");
            }
        }
    }
}
