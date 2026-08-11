using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Cleaning;

/// <summary>
/// Clears Windows Update's local download cache and the Delivery Optimization cache.
/// Both are safe to delete - Windows re-downloads whatever it still needs - but both
/// are machine-wide and typically locked while the Windows Update / Delivery
/// Optimization services are running, so failures here are expected and non-fatal;
/// DryRunEngine reports them as per-item failures rather than aborting the clean.
/// </summary>
public sealed class WindowsUpdateTarget : CleanTargetBase, ICleanTarget
{
    private readonly string _windowsDirectory;

    public WindowsUpdateTarget(IFileSystem fileSystem, IPathGuard guard, string windowsDirectory)
        : base(fileSystem, guard)
    {
        _windowsDirectory = windowsDirectory;
    }

    public CleanCategory Category => CleanCategory.WindowsUpdate;
    public string DisplayName => "Windows Update Leftovers";
    public bool RequiresElevation => true;

    public ScanResult Scan()
    {
        var softwareDistributionDownload = FileSystem.Path.Combine(_windowsDirectory, "SoftwareDistribution", "Download");
        var deliveryOptimizationCache = FileSystem.Path.Combine(
            _windowsDirectory, "ServiceProfiles", "NetworkService", "AppData", "Local",
            "Microsoft", "Windows", "DeliveryOptimization", "Cache");

        var candidates = SafeGetFiles(softwareDistributionDownload)
            .Concat(SafeGetDirectories(softwareDistributionDownload))
            .Concat(SafeGetFiles(deliveryOptimizationCache))
            .Concat(SafeGetDirectories(deliveryOptimizationCache));

        return BuildScanResult(Category, candidates);
    }
}
