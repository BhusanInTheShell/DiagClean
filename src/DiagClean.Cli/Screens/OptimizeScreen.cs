using DiagClean.Core.Models;
using DiagClean.Core.Optimize;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

public static class OptimizeScreen
{
    public static void Run(IReadOnlyList<IOptimizationAction> actions, bool assumeYes, bool previewOnly)
    {
        if (actions.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No optimization actions available for this platform.[/]");
            return;
        }

        var selected = AnsiConsole.Prompt(
            new MultiSelectionPrompt<IOptimizationAction>()
                .Title("Select optimizations to run")
                .PageSize(15)
                .InstructionsText("[grey](use space to select, enter to confirm)[/]")
                .UseConverter(Describe)
                .AddChoices(actions));

        if (selected.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No optimizations selected.[/]");
            return;
        }

        var table = new Table().Border(TableBorder.Rounded).Title("Selected optimizations");
        table.AddColumn("Action");
        table.AddColumn("Details");
        foreach (var action in selected)
        {
            table.AddRow(Markup.Escape(action.Name), Markup.Escape(action.Description));
        }

        AnsiConsole.Write(table);

        if (previewOnly)
        {
            AnsiConsole.MarkupLine("[grey]Dry-run only - nothing was run.[/]");
            return;
        }

        var slowActions = selected.Where(a => a.IsSlow).ToList();
        if (slowActions.Count > 0 && !assumeYes)
        {
            var names = string.Join(", ", slowActions.Select(a => a.Name));
            if (!AnsiConsole.Confirm(
                    $"[yellow]{Markup.Escape(names)}[/] can take minutes to hours and will keep running in the " +
                    "background after this tool exits. Continue?", defaultValue: false))
            {
                AnsiConsole.MarkupLine("[yellow]Cancelled.[/]");
                return;
            }
        }

        if (!assumeYes && !AnsiConsole.Confirm($"Run {selected.Count} optimization(s) now?"))
        {
            AnsiConsole.MarkupLine("[yellow]Cancelled.[/]");
            return;
        }

        var results = new List<(IOptimizationAction Action, OptimizationResult Result)>();
        AnsiConsole.Progress()
            .Columns(new TaskDescriptionColumn(), new ProgressBarColumn(), new PercentageColumn(), new SpinnerColumn())
            .Start(ctx =>
            {
                foreach (var action in selected)
                {
                    var task = ctx.AddTask(action.Name, maxValue: 1);
                    results.Add((action, action.Run()));
                    task.Value = 1;
                }
            });

        PrintOutcomeSummary(results);
        OptimizeRunLogger.Log(results);
    }

    private static string Describe(IOptimizationAction action)
    {
        var tags = new List<string>();
        if (action.RequiresElevation)
        {
            tags.Add("needs admin");
        }

        if (action.IsSlow)
        {
            tags.Add("slow");
        }

        var suffix = tags.Count > 0 ? $" [grey]({string.Join(", ", tags)})[/]" : "";
        return $"{action.Name}{suffix} - {action.Description}";
    }

    private static void PrintOutcomeSummary(List<(IOptimizationAction Action, OptimizationResult Result)> results)
    {
        var succeeded = results.Count(r => r.Result.Success);
        var failed = results.Count - succeeded;

        AnsiConsole.MarkupLine($"\n[green bold]Done.[/] {succeeded} succeeded, {failed} failed.");

        foreach (var (action, result) in results)
        {
            var icon = result.Success ? "[green]✓[/]" : "[red]✗[/]";
            AnsiConsole.MarkupLine($"  {icon} {Markup.Escape(action.Name)}: {Markup.Escape(result.Message)}");
        }
    }
}
