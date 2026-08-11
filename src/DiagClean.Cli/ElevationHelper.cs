using System.Runtime.Versioning;
using System.Security.Principal;

namespace DiagClean.Cli;

public static class ElevationHelper
{
    public static bool IsRunningAsAdministrator()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        return IsAdministratorWindows();
    }

    [SupportedOSPlatform("windows")]
    private static bool IsAdministratorWindows()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }
}
