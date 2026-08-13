using System.Text;
using DiagClean.Core.Models;
using DiagClean.Core.Optimize;

namespace DiagClean.Cli;

/// <summary>Same audit-trail purpose as CleanRunLogger/UninstallRunLogger.</summary>
public static class OptimizeRunLogger
{
    public static void Log(IReadOnlyList<(IOptimizationAction Action, OptimizationResult Result)> results)
    {
        Directory.CreateDirectory(AppPaths.LogsDirectory);
        var logFile = Path.Combine(AppPaths.LogsDirectory, $"optimize-{DateTime.Now:yyyy-MM-dd}.log");

        var sb = new StringBuilder();
        sb.AppendLine($"---- Optimize run at {DateTimeOffset.Now:u} by {Environment.UserName} on {Environment.MachineName} ----");

        foreach (var (action, result) in results)
        {
            sb.AppendLine($"[{action.Name}] success: {result.Success} - {result.Message}");
        }

        sb.AppendLine();
        File.AppendAllText(logFile, sb.ToString());
    }
}
