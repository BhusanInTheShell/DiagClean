using System.ComponentModel;
using System.IO.Abstractions;
using DiagClean.Cli.Screens;
using DiagClean.Core.Analyze;
using Spectre.Console;
using Spectre.Console.Cli;

namespace DiagClean.Cli.Commands;

public sealed class AnalyzeCommand : Command<AnalyzeCommand.Settings>
{
    public sealed class Settings : CommandSettings
    {
        [CommandOption("-p|--path <PATH>")]
        [Description("Directory to start browsing from. Defaults to your home directory.")]
        public string? Path { get; set; }
    }

    public override int Execute(CommandContext context, Settings settings)
    {
        if (!OperatingSystem.IsWindows() && !OperatingSystem.IsMacOS())
        {
            AnsiConsole.MarkupLine("[red]Analyze requires Windows or macOS.[/]");
            return 1;
        }

        IFileSystem fileSystem = new FileSystem();
        var startPath = settings.Path ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        if (!fileSystem.Directory.Exists(startPath))
        {
            AnsiConsole.MarkupLine($"[red]Directory not found: {Markup.Escape(startPath)}[/]");
            return 1;
        }

        var analyzer = AnalyzeFactory.Create(fileSystem);
        AnalyzeScreen.Run(analyzer, fileSystem, startPath);
        return 0;
    }
}
