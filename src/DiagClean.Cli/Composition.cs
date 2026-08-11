using System.IO.Abstractions;
using System.Runtime.Versioning;
using DiagClean.Core.Cleaning;
using DiagClean.Core.Diagnostics;

namespace DiagClean.Cli;

[SupportedOSPlatform("windows")]
public static class Composition
{
    public static DiagnosticCollectorService CreateDiagnosticService() =>
        new(
            new HardwareCollector(),
            new DiskHealthCollector(),
            new EventLogCollector(),
            new SoftwareInventoryCollector(),
            new NetworkCollector(),
            new PerformanceCollector());

    public static IReadOnlyList<ICleanTarget> CreateCleanTargets(AppSettingsModel settings)
    {
        IFileSystem fileSystem = new FileSystem();
        return CleanTargetFactory.CreateDefaultTargets(fileSystem, settings.ProtectedPaths);
    }
}
