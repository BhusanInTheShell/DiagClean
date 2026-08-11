using System.Text;
using DiagClean.Core.Models;

namespace DiagClean.Cli;

/// <summary>
/// Appends a plain-text audit record of every clean run to a per-day log file, so a
/// technician can show exactly what was touched on a machine if it's ever questioned.
/// </summary>
public static class CleanRunLogger
{
    public static void Log(IReadOnlyList<CleanOutcome> outcomes)
    {
        Directory.CreateDirectory(AppPaths.LogsDirectory);
        var logFile = Path.Combine(AppPaths.LogsDirectory, $"clean-{DateTime.Now:yyyy-MM-dd}.log");

        var sb = new StringBuilder();
        sb.AppendLine($"---- Clean run at {DateTimeOffset.Now:u} by {Environment.UserName} on {Environment.MachineName} ----");

        foreach (var outcome in outcomes)
        {
            sb.AppendLine($"[{outcome.Category}] {outcome.ItemsDeleted} items deleted, " +
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
