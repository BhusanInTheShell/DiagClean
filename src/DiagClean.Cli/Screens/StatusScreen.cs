using DiagClean.Core.Models;
using DiagClean.Core.Status;
using Spectre.Console;
using Spectre.Console.Rendering;

namespace DiagClean.Cli.Screens;

/// <summary>
/// A live-refreshing health dashboard via Spectre.Console's Live display. The refresh
/// cadence isn't a fixed timer - it's paced by ISystemStatusCollector.Collect() itself,
/// which blocks for roughly 1-2 seconds while sampling rate-based metrics (confirmed
/// live: ~2.25s on this machine, dominated by the CPU/disk-I/O and network delta
/// samples). Quit is checked between refreshes, not during a collection - worst case,
/// pressing Q takes one refresh cycle to register, which is an acceptable tradeoff
/// given real system metrics can't be sampled meaningfully any faster than that anyway.
/// </summary>
public static class StatusScreen
{
    public static void Run(ISystemStatusCollector collector, bool once)
    {
        if (once)
        {
            AnsiConsole.Write(BuildLayout(collector.Collect()));
            return;
        }

        if (Console.IsInputRedirected)
        {
            AnsiConsole.MarkupLine(
                "[red]Status's live dashboard requires an interactive terminal.[/] Use [bold]--once[/] for a single snapshot instead.");
            return;
        }

        AnsiConsole.MarkupLine("[grey]Press Q to quit.[/]\n");

        AnsiConsole.Live(BuildLayout(collector.Collect()))
            .AutoClear(false)
            .Start(ctx =>
            {
                while (true)
                {
                    if (Console.KeyAvailable)
                    {
                        var key = Console.ReadKey(intercept: true);
                        if (key.Key is ConsoleKey.Q or ConsoleKey.Escape)
                        {
                            break;
                        }
                    }

                    ctx.UpdateTarget(BuildLayout(collector.Collect()));
                    ctx.Refresh();
                }
            });

        AnsiConsole.MarkupLine("\n[grey]Status closed.[/]");
    }

    private static IRenderable BuildLayout(SystemStatusSnapshot s)
    {
        var left = new Rows(BuildCpuPanel(s), BuildDiskPanel(s));
        var right = new Rows(BuildMemoryPanel(s), BuildNetworkAndPowerPanel(s));

        return new Rows(
            new Columns(left, right) { Expand = false },
            BuildProcessesPanel(s));
    }

    private static IRenderable BuildCpuPanel(SystemStatusSnapshot s)
    {
        var lines = new List<string> { $"Total  {FormatUtils.RenderBar(s.CpuPercent)}  {s.CpuPercent,5:0.0}%" };
        if (s.LoadAverage1Min is not null)
        {
            lines.Add($"Load   {s.LoadAverage1Min:0.00} / {s.LoadAverage5Min:0.00} / {s.LoadAverage15Min:0.00} ({Environment.ProcessorCount} cores)");
        }

        return new Panel(string.Join('\n', lines)) { Header = new PanelHeader("CPU") };
    }

    private static IRenderable BuildMemoryPanel(SystemStatusSnapshot s)
    {
        var lines = new[]
        {
            $"Used   {FormatUtils.RenderBar(s.MemoryUsedPercent)}  {s.MemoryUsedPercent,5:0.0}%",
            $"Total  {s.MemoryUsedGb:0.#} / {s.MemoryTotalGb:0.#} GB"
        };

        return new Panel(string.Join('\n', lines)) { Header = new PanelHeader("Memory") };
    }

    private static IRenderable BuildDiskPanel(SystemStatusSnapshot s)
    {
        var lines = new[]
        {
            $"Used   {FormatUtils.RenderBar(s.DiskUsedPercent)}  {s.DiskUsedPercent,5:0.0}%",
            $"Free   {s.DiskFreeGb:0.#} / {s.DiskTotalGb:0.#} GB",
            $"I/O    {FormatUtils.FormatRate(s.DiskActivityBytesPerSecond)}"
        };

        return new Panel(string.Join('\n', lines)) { Header = new PanelHeader("Disk") };
    }

    private static IRenderable BuildNetworkAndPowerPanel(SystemStatusSnapshot s)
    {
        var lines = new List<string>
        {
            $"Down   {FormatUtils.FormatRate(s.NetworkDownloadBytesPerSecond)}",
            $"Up     {FormatUtils.FormatRate(s.NetworkUploadBytesPerSecond)}"
        };

        if (s.BatteryPercent is not null)
        {
            var status = s.BatteryCharging == true ? "charging" : "discharging";
            lines.Add($"Power  {FormatUtils.RenderBar(s.BatteryPercent.Value)}  {s.BatteryPercent}% ({status})");
        }

        return new Panel(string.Join('\n', lines)) { Header = new PanelHeader("Network") };
    }

    private static IRenderable BuildProcessesPanel(SystemStatusSnapshot s)
    {
        if (s.TopProcesses.Count == 0)
        {
            return new Panel("[grey](no data)[/]") { Header = new PanelHeader("Top Processes") };
        }

        var lines = s.TopProcesses.Select(p =>
            $"{Markup.Escape(p.Name),-24} {FormatUtils.RenderBar(p.CpuPercent, 10)}  {p.CpuPercent,5:0.0}%");

        return new Panel(string.Join('\n', lines)) { Header = new PanelHeader("Top Processes") };
    }
}
