using System.Text;
using DiagClean.Core.Models;

namespace DiagClean.Cli;

/// <summary>
/// Same audit-trail purpose as CleanRunLogger, kept separate since Uninstall's outcome
/// shape (AppRemoved, per-app leftover counts) doesn't fit CleanOutcome's category-based
/// one.
/// </summary>
public static class UninstallRunLogger
{
    public static void Log(IReadOnlyList<UninstallOutcome> outcomes)
    {
        Directory.CreateDirectory(AppPaths.LogsDirectory);
        var logFile = Path.Combine(AppPaths.LogsDirectory, $"uninstall-{DateTime.Now:yyyy-MM-dd}.log");

        var sb = new StringBuilder();
        sb.AppendLine($"---- Uninstall run at {DateTimeOffset.Now:u} by {Environment.UserName} on {Environment.MachineName} ----");

        foreach (var outcome in outcomes)
        {
            sb.AppendLine($"[{outcome.App.Name}] app removed: {outcome.AppRemoved}, " +
                          $"{outcome.LeftoverItemsRemoved} leftover item(s) removed, " +
                          $"{FormatUtils.FormatSize(outcome.BytesFreed)} freed, {outcome.Failures.Count} failure(s)");

            foreach (var failure in outcome.Failures)
            {
                sb.AppendLine($"    FAILED: {failure.FullPath} - {failure.Reason}");
            }
        }

        sb.AppendLine();
        File.AppendAllText(logFile, sb.ToString());
    }
}
