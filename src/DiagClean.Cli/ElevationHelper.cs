namespace DiagClean.Cli;

public static class ElevationHelper
{
    // Cross-platform since .NET 8: true when running as Administrator on Windows or
    // root on macOS/Linux. Replaces separate WindowsPrincipal/geteuid checks.
    public static bool IsRunningAsAdministrator() => Environment.IsPrivilegedProcess;
}
