using System.Diagnostics;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Optimize.Windows;

/// <summary>
/// Windows counterparts to the macOS actions - same conservative scope (common,
/// well-known helpdesk fixes), documented against known Windows behavior but not
/// exercised on a real Windows machine (see SMOKE_TEST.md), same as the rest of the
/// Windows-only surface in this project.
///
/// Deliberately *not* marked [SupportedOSPlatform("windows")] - nothing here calls a
/// genuinely BCL-gated API (ipconfig/taskkill/net are just process arguments, not
/// platform-restricted .NET APIs), which means the action list's shape can be
/// unit-tested on any OS, same reasoning as WindowsAppUninstaller.
/// </summary>
public static class WindowsOptimizationActions
{
    public static IReadOnlyList<IOptimizationAction> All =>
    [
        new DelegateOptimizationAction(
            "Flush DNS Cache",
            "Clears the local DNS resolver cache - fixes \"can't reach this site\" issues after a DNS change.",
            requiresElevation: false,
            isSlow: false,
            FlushDns),

        new DelegateOptimizationAction(
            "Rebuild Icon Cache",
            "Clears the shell icon cache - fixes wrong, blank, or generic icons in " +
            "Explorer. Restarts Explorer as part of the fix (windows briefly disappear and come back).",
            requiresElevation: false,
            isSlow: false,
            RebuildIconCache),

        new DelegateOptimizationAction(
            "Restart Windows Explorer",
            "Restarts explorer.exe - fixes a frozen taskbar, Start Menu, or file " +
            "windows without a full reboot.",
            requiresElevation: false,
            isSlow: false,
            RestartExplorerAction),

        new DelegateOptimizationAction(
            "Reset Print Spooler",
            "Stops the Print Spooler service, clears stuck print jobs, and restarts it " +
            "- fixes a printer stuck \"Printing\" or unresponsive.",
            requiresElevation: true,
            isSlow: false,
            ResetPrintSpooler),
    ];

    private static OptimizationResult FlushDns()
    {
        var result = ShellRunner.RunWithExitCode("ipconfig", ["/flushdns"], TimeSpan.FromSeconds(10));
        return new OptimizationResult
        {
            Success = result.Succeeded,
            Message = result.Succeeded ? "DNS cache flushed." : "Couldn't flush the DNS cache."
        };
    }

    private static OptimizationResult RebuildIconCache()
    {
        try
        {
            KillExplorer();

            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var explorerDir = Path.Combine(localAppData, "Microsoft", "Windows", "Explorer");
            var legacyIconCache = Path.Combine(localAppData, "IconCache.db");

            if (Directory.Exists(explorerDir))
            {
                foreach (var file in Directory.EnumerateFiles(explorerDir, "iconcache_*.db"))
                {
                    File.Delete(file);
                }
            }

            if (File.Exists(legacyIconCache))
            {
                File.Delete(legacyIconCache);
            }

            StartExplorer();
            return new OptimizationResult { Success = true, Message = "Icon cache cleared and Explorer restarted." };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            StartExplorer(); // Best-effort - don't leave the user without a shell.
            return new OptimizationResult
            {
                Success = false,
                Message = $"Couldn't clear the icon cache: {ex.Message}"
            };
        }
    }

    private static OptimizationResult RestartExplorerAction()
    {
        try
        {
            KillExplorer();
            StartExplorer();
            return new OptimizationResult { Success = true, Message = "Explorer restarted." };
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException)
        {
            return new OptimizationResult { Success = false, Message = $"Couldn't restart Explorer: {ex.Message}" };
        }
    }

    private static OptimizationResult ResetPrintSpooler()
    {
        var stop = ShellRunner.RunWithExitCode("net", ["stop", "spooler"], TimeSpan.FromSeconds(30));
        if (!stop.Succeeded)
        {
            return new OptimizationResult
            {
                Success = false,
                Message = "Couldn't stop the Print Spooler service - re-run elevated (Administrator)."
            };
        }

        try
        {
            var spoolDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System), "spool", "PRINTERS");

            if (Directory.Exists(spoolDir))
            {
                foreach (var file in Directory.EnumerateFiles(spoolDir))
                {
                    try
                    {
                        File.Delete(file);
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                    {
                        // Skip individual locked job files rather than abort the whole reset.
                    }
                }
            }
        }
        finally
        {
            // Always try to bring the service back, even if clearing the queue failed
            // partway through - leaving printing disabled would be worse than the
            // original problem.
            ShellRunner.RunWithExitCode("net", ["start", "spooler"], TimeSpan.FromSeconds(30));
        }

        return new OptimizationResult { Success = true, Message = "Print Spooler reset and stuck jobs cleared." };
    }

    private static void KillExplorer() =>
        ShellRunner.RunWithExitCode("taskkill", ["/F", "/IM", "explorer.exe"], TimeSpan.FromSeconds(10));

    private static void StartExplorer() =>
        Process.Start(new ProcessStartInfo("explorer.exe") { UseShellExecute = true });
}
