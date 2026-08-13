using System.IO.Abstractions;
using System.Runtime.Versioning;
using DiagClean.Core.Analyze.Mac;

namespace DiagClean.Core.Analyze;

public static class AnalyzeFactory
{
    public static IDirectoryAnalyzer Create(IFileSystem fileSystem)
    {
        // Same reasoning and pattern as UninstallFactory/OptimizeFactory - the call
        // into the platform-gated Mac implementation must stay directly inside this
        // guard for the platform-compatibility analyzer to trace it.
        if (OperatingSystem.IsMacOS())
        {
            return CreateMac();
        }

        return new DirectoryAnalyzer(fileSystem);
    }

    [SupportedOSPlatform("macos")]
    private static IDirectoryAnalyzer CreateMac() => new MacDirectoryAnalyzer();
}
