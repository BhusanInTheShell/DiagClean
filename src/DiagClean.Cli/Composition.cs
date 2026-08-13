using System.IO.Abstractions;
using DiagClean.Core.Cleaning;
using DiagClean.Core.Diagnostics;
using DiagClean.Core.Diagnostics.Mac;
using DiagClean.Core.Uninstall;

namespace DiagClean.Cli;

public static class Composition
{
    public static DiagnosticCollectorService CreateDiagnosticService()
    {
        if (OperatingSystem.IsWindows())
        {
            return new DiagnosticCollectorService(
                new HardwareCollector(),
                new DiskHealthCollector(),
                new EventLogCollector(),
                new SoftwareInventoryCollector(),
                new NetworkCollector(),
                new PerformanceCollector());
        }

        if (OperatingSystem.IsMacOS())
        {
            // NetworkCollector uses System.Net.NetworkInformation, which is genuinely
            // cross-platform - no macOS-specific variant needed.
            return new DiagnosticCollectorService(
                new MacHardwareCollector(),
                new MacDiskHealthCollector(),
                new MacSystemLogCollector(),
                new MacSoftwareInventoryCollector(),
                new NetworkCollector(),
                new MacPerformanceCollector());
        }

        throw new PlatformNotSupportedException("DiagClean supports Windows and macOS only.");
    }

    public static IReadOnlyList<ICleanTarget> CreateCleanTargets(AppSettingsModel settings)
    {
        IFileSystem fileSystem = new FileSystem();
        return CleanTargetFactory.CreateDefaultTargets(fileSystem, settings.ProtectedPaths);
    }

    public static (IAppLister Lister, IAppUninstaller Uninstaller) CreateUninstall()
    {
        var settings = AppSettingsModel.Load(AppPaths.SettingsFilePath);
        IFileSystem fileSystem = new FileSystem();
        return UninstallFactory.Create(fileSystem, settings.ProtectedPaths);
    }
}
