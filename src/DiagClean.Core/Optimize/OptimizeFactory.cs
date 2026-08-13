using DiagClean.Core.Optimize.Mac;
using DiagClean.Core.Optimize.Windows;

namespace DiagClean.Core.Optimize;

public static class OptimizeFactory
{
    public static IReadOnlyList<IOptimizationAction> Create()
    {
        // Calls into the OS-specific action lists must stay directly inside these
        // guards - same pattern and reasoning as UninstallFactory.Create.
        if (OperatingSystem.IsWindows())
        {
            return WindowsOptimizationActions.All;
        }

        if (OperatingSystem.IsMacOS())
        {
            return MacOptimizationActions.All;
        }

        throw new PlatformNotSupportedException("DiagClean supports Windows and macOS only.");
    }
}
