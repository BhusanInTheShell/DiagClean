using System.Diagnostics;

namespace DiagClean.Core.Shell;

/// <summary>
/// Runs a system CLI tool and captures stdout. macOS (and eventually Linux) diagnostics
/// have no WMI equivalent - shelling out to system_profiler/diskutil/sysctl/log/vm_stat
/// is the standard, idiomatic way native macOS tools gather this data, since it avoids
/// hand-rolled Objective-C/Mach interop for a helpdesk-scale tool. Every call is bounded
/// by a timeout so one hung subprocess can't hang the whole collector.
/// </summary>
public static class ShellRunner
{
    public static string? Run(string fileName, string arguments, TimeSpan? timeout = null) =>
        Run(fileName, SplitArguments(arguments), timeout);

    /// <summary>
    /// Preferred overload - each element becomes exactly one argument via
    /// ProcessStartInfo.ArgumentList, with no shell-quoting ambiguity. Required for
    /// arguments containing spaces (log show predicates, paths with spaces).
    /// </summary>
    public static string? Run(string fileName, IReadOnlyList<string> arguments, TimeSpan? timeout = null)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = fileName,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            foreach (var arg in arguments)
            {
                startInfo.ArgumentList.Add(arg);
            }

            using var process = new Process { StartInfo = startInfo };

            process.Start();

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var completed = process.WaitForExit((int)(timeout ?? TimeSpan.FromSeconds(15)).TotalMilliseconds);

            if (!completed)
            {
                TryKill(process);
                return null;
            }

            return outputTask.GetAwaiter().GetResult();
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException)
        {
            // Binary not found or not executable on this machine - degrade gracefully.
            return null;
        }
    }

    private static string[] SplitArguments(string arguments) =>
        arguments.Length == 0 ? [] : arguments.Split(' ', StringSplitOptions.RemoveEmptyEntries);

    private static void TryKill(Process process)
    {
        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch (InvalidOperationException)
        {
            // Already exited between the timeout check and the kill attempt.
        }
    }
}
