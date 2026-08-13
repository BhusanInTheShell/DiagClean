using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Uninstall;

/// <summary>
/// Whether the OS lets DiagClean remove an app directly, or only through the app's own
/// registered uninstaller. macOS apps are self-contained bundles - moving one to Trash
/// (recoverable, unlike a hard delete) is a complete, standard removal. Windows has no
/// equivalent generic primitive: deleting a Program Files folder without running the
/// vendor's uninstaller leaves orphaned registry entries, services, and shortcuts behind.
/// </summary>
public enum UninstallMethod
{
    DirectRemoval,
    VendorUninstaller
}

public interface IAppUninstaller
{
    UninstallMethod Method { get; }

    /// <summary>The guard this uninstaller scans with - callers must reuse it for the
    /// removal-time re-check, same pattern as Cleaning's DryRunEngine.</summary>
    IPathGuard Guard { get; }

    AppLeftoverScanResult ScanLeftovers(InstalledApp app);

    /// <summary>
    /// DirectRemoval only: moves the app bundle and the given (already-confirmed)
    /// leftover items to a recoverable trash location.
    /// </summary>
    UninstallOutcome RemoveDirectly(InstalledApp app, IReadOnlyList<AppLeftoverItem> leftoverItems);

    /// <summary>
    /// VendorUninstaller only: launches the app's own registered uninstaller and blocks
    /// until it exits. Does not force silent/unattended flags - third-party uninstallers
    /// use inconsistent conventions (NSIS, InnoSetup, MSI, custom) and guessing wrong
    /// risks a broken or partial removal, so the vendor's own UI runs as intended.
    /// </summary>
    bool RunVendorUninstaller(InstalledApp app);
}
