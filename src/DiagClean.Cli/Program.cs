using DiagClean.Cli.Commands;
using DiagClean.Cli.Screens;
using QuestPDF.Infrastructure;
using Spectre.Console.Cli;

// QuestPDF requires a license selection before any document is generated. Community is
// free for small teams/companies (see https://www.questpdf.com/license/) - revisit this
// if DiagClean is ever deployed at a scale that falls outside those terms.
QuestPDF.Settings.License = LicenseType.Community;

if (args.Length == 0)
{
    if (Console.IsInputRedirected)
    {
        // No TTY to prompt against - Spectre.Console throws NotSupportedException from
        // deep inside MainMenuScreen.Run() if this isn't caught up front, crashing with
        // an unhandled-exception stack trace instead of a usable message. Any launch
        // context without a real terminal hits this: RMM/remote exec, a CI installer
        // validation sandbox invoking the exe to confirm it runs, `dclean < /dev/null`.
        Console.WriteLine("DiagClean's interactive menu requires a terminal. Run 'dclean --help' for available commands.");
        return 0;
    }

    MainMenuScreen.Run();
    return 0;
}

var app = new CommandApp();
app.Configure(config =>
{
    config.SetApplicationName("dclean");
    config.AddCommand<DiagCommand>("diag")
        .WithDescription("Collect a diagnostic report and write it as HTML and/or PDF.")
        .WithExample("diag", "--output", "C:\\reports\\machine1.html")
        .WithExample("diag", "--format", "pdf", "--output", "C:\\reports\\machine1.pdf");

    config.AddCommand<CleanCommand>("clean")
        .WithDescription("Scan and clean temp files, browser caches, and Windows Update leftovers.")
        .WithExample("clean", "--preset", "quick", "--dry-run")
        .WithExample("clean", "--preset", "deep", "--yes");

    config.AddCommand<UninstallCommand>("uninstall")
        .WithDescription("Remove apps and their leftover files (caches, preferences, logs).")
        .WithExample("uninstall", "--dry-run")
        .WithExample("uninstall", "--yes");
});

return app.Run(args);
