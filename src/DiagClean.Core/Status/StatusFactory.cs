using System.Runtime.Versioning;
using DiagClean.Core.Status.Mac;
using DiagClean.Core.Status.Windows;

namespace DiagClean.Core.Status;

public static class StatusFactory
{
    public static ISystemStatusCollector Create()
    {
        // Same pattern and reasoning as UninstallFactory/OptimizeFactory/AnalyzeFactory
        // - calls into the platform-gated collectors must stay directly inside these
        // guards for the platform-compatibility analyzer to trace it.
        if (OperatingSystem.IsWindows())
        {
            return CreateWindows();
        }

        if (OperatingSystem.IsMacOS())
        {
            return CreateMac();
        }

        throw new PlatformNotSupportedException("DiagClean supports Windows and macOS only.");
    }

    [SupportedOSPlatform("windows")]
    private static ISystemStatusCollector CreateWindows() => new WindowsSystemStatusCollector();

    [SupportedOSPlatform("macos")]
    private static ISystemStatusCollector CreateMac() => new MacSystemStatusCollector();
}
