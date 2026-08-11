using DiagClean.Cli.Commands;
using DiagClean.Cli.Screens;
using Spectre.Console.Cli;

if (args.Length == 0)
{
    MainMenuScreen.Run();
    return 0;
}

var app = new CommandApp();
app.Configure(config =>
{
    config.SetApplicationName("DiagClean");
    config.AddCommand<DiagCommand>("diag")
        .WithDescription("Collect a diagnostic report and write it as HTML.")
        .WithExample("diag", "--output", "C:\\reports\\machine1.html");

    config.AddCommand<CleanCommand>("clean")
        .WithDescription("Scan and clean temp files, browser caches, and Windows Update leftovers.")
        .WithExample("clean", "--preset", "quick", "--dry-run")
        .WithExample("clean", "--preset", "deep", "--yes");
});

return app.Run(args);
