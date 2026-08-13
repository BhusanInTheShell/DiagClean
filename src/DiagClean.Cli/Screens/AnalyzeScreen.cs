using System.Diagnostics;
using System.IO.Abstractions;
using DiagClean.Core.Analyze;
using DiagClean.Core.Models;
using Spectre.Console;

namespace DiagClean.Cli.Screens;

/// <summary>
/// A navigable disk usage browser. Built on Spectre.Console's SelectionPrompt (select an
/// entry, then act) rather than a raw-keyboard live-redraw UI: real directory scans
/// (even with the fast macOS `du` path) can take several seconds on large real-world
/// trees - confirmed live scanning ~40GB of ~/Library, 14 seconds - so a UI implying
/// instant per-keystroke feedback would just feel broken. SelectionPrompt also means
/// this correctly refuses to run without an interactive terminal (Spectre.Console's own
/// behavior), consistent with the rest of the app, rather than needing bespoke handling.
/// </summary>
public static class AnalyzeScreen
{
    public static void Run(IDirectoryAnalyzer analyzer, IFileSystem fileSystem, string startPath)
    {
        var currentPath = fileSystem.Path.TrimEndingDirectorySeparator(startPath);

        while (true)
        {
            IReadOnlyList<DiskEntry> children = [];
            AnsiConsole.Status()
                .Spinner(Spinner.Known.Dots)
                .Start($"Scanning {currentPath}...", _ => children = analyzer.GetChildren(currentPath));

            var totalBytes = children.Sum(c => c.SizeBytes);
            var parent = fileSystem.Path.GetDirectoryName(currentPath);

            var items = new List<NavItem>();
            if (!string.IsNullOrEmpty(parent))
            {
                items.Add(new NavItem { Label = ".. (go up)", IsGoUp = true });
            }

            items.AddRange(children.Select(entry => new NavItem { Label = FormatEntry(entry, totalBytes), Entry = entry }));
            items.Add(new NavItem { Label = "[grey]Quit Analyze[/]", IsQuit = true });

            var choice = AnsiConsole.Prompt(
                new SelectionPrompt<NavItem>()
                    .Title($"[bold]Analyze Disk[/]  {Markup.Escape(currentPath)}  |  Total: {FormatUtils.FormatSize(totalBytes)}")
                    .PageSize(20)
                    .MoreChoicesText("[grey](move up/down to see more)[/]")
                    .UseConverter(i => i.Label)
                    .AddChoices(items));

            if (choice.IsQuit)
            {
                return;
            }

            if (choice.IsGoUp)
            {
                currentPath = parent!;
                continue;
            }

            var selected = choice.Entry!;
            var action = PromptEntryAction(selected);

            switch (action)
            {
                case EntryAction.Enter:
                    currentPath = selected.FullPath;
                    break;
                case EntryAction.Open:
                    TryLaunch(selected.FullPath, reveal: false);
                    break;
                case EntryAction.Reveal:
                    TryLaunch(selected.FullPath, reveal: true);
                    break;
                case EntryAction.Delete:
                    TryDelete(fileSystem, selected);
                    break;
                case EntryAction.Cancel:
                    break;
            }
        }
    }

    private static EntryAction PromptEntryAction(DiskEntry entry)
    {
        var choices = entry.IsDirectory
            ? new[] { "Enter this folder", "Reveal in Finder/Explorer", "Delete", "Cancel" }
            : ["Open", "Reveal in Finder/Explorer", "Delete", "Cancel"];

        var label = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title($"{Markup.Escape(entry.Name)}  ({FormatUtils.FormatSize(entry.SizeBytes)})")
                .AddChoices(choices));

        return label switch
        {
            "Enter this folder" => EntryAction.Enter,
            "Open" => EntryAction.Open,
            "Reveal in Finder/Explorer" => EntryAction.Reveal,
            "Delete" => EntryAction.Delete,
            _ => EntryAction.Cancel
        };
    }

    private static void TryDelete(IFileSystem fileSystem, DiskEntry entry)
    {
        var recoverable = OperatingSystem.IsMacOS();
        var consequence = recoverable
            ? "moved to Trash (recoverable)"
            : "[red]permanently deleted - this cannot be undone[/]";

        AnsiConsole.MarkupLine(
            $"\n{Markup.Escape(entry.FullPath)}\nSize: {FormatUtils.FormatSize(entry.SizeBytes)}\nWill be {consequence}.");

        var response = AnsiConsole.Prompt(
            new TextPrompt<string>("Type [bold red]DELETE[/] to confirm, or press Enter to cancel:").AllowEmpty());

        if (!string.Equals(response, "DELETE", StringComparison.Ordinal))
        {
            AnsiConsole.MarkupLine("[yellow]Cancelled.[/]");
            return;
        }

        var result = AnalyzeDeleter.Delete(fileSystem, entry);
        AnsiConsole.MarkupLine(result.Success
            ? $"[green]Done.[/] {Markup.Escape(entry.Name)} was {(result.Method == DeleteMethod.MovedToTrash ? "moved to Trash" : "permanently deleted")}."
            : $"[red]Failed:[/] {Markup.Escape(result.ErrorMessage ?? "unknown error")}");
    }

    private static void TryLaunch(string path, bool reveal)
    {
        try
        {
            if (OperatingSystem.IsMacOS())
            {
                var openInfo = new ProcessStartInfo("open");
                if (reveal)
                {
                    openInfo.ArgumentList.Add("-R");
                }

                openInfo.ArgumentList.Add(path);
                Process.Start(openInfo);
            }
            else if (OperatingSystem.IsWindows())
            {
                var startInfo = reveal
                    ? new ProcessStartInfo("explorer.exe") { ArgumentList = { $"/select,{path}" } }
                    : new ProcessStartInfo(path) { UseShellExecute = true };
                Process.Start(startInfo);
            }
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            AnsiConsole.MarkupLine($"[yellow]Couldn't open it: {Markup.Escape(ex.Message)}[/]");
        }
    }

    private static string FormatEntry(DiskEntry entry, long totalBytes)
    {
        var pct = totalBytes > 0 ? (double)entry.SizeBytes / totalBytes * 100 : 0;
        var bar = FormatUtils.RenderBar(pct);
        var icon = entry.IsDirectory ? "\U0001F4C1" : "\U0001F4C4"; // 📁 / 📄
        var name = Markup.Escape(entry.Name);
        return $"{bar} {pct,5:0.0}%  {icon} {name,-40} {FormatUtils.FormatSize(entry.SizeBytes),10}";
    }

    private enum EntryAction { Enter, Open, Reveal, Delete, Cancel }

    private sealed class NavItem
    {
        public required string Label { get; init; }
        public DiskEntry? Entry { get; init; }
        public bool IsGoUp { get; init; }
        public bool IsQuit { get; init; }
    }
}
