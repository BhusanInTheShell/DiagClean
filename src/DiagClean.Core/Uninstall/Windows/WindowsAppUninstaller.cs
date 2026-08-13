using System.Diagnostics;
using System.IO.Abstractions;
using DiagClean.Core.Models;
using DiagClean.Core.Safety;

namespace DiagClean.Core.Uninstall.Windows;

/// <summary>
/// Removing the app itself is delegated entirely to its own registered uninstaller
/// (RunVendorUninstaller) - there's no Windows equivalent of "move the bundle to
/// Trash" that leaves the system in a consistent state, unlike macOS. RemoveDirectly
/// here only ever touches the *residual* AppData folders the vendor uninstaller left
/// behind, matched by app name (there's no bundle-identifier equivalent to key off on
/// Windows) - a narrower, lower-stakes cleanup than removing the app itself, and one
/// already-proven code path: it deletes the same way Clean's DryRunEngine does, rather
/// than introducing an unverified Recycle-Bin API this project has no way to test
/// against a real Windows machine.
///
/// Deliberately *not* marked [SupportedOSPlatform("windows")] - unlike WindowsAppLister
/// (registry access), nothing here actually calls a Windows-only API, which means it
/// can be unit-tested with a fake filesystem on any OS, same as the Clean targets.
/// </summary>
public sealed class WindowsAppUninstaller : IAppUninstaller
{
    private readonly IFileSystem _fileSystem;
    private readonly IReadOnlyList<string> _leftoverRoots;

    public WindowsAppUninstaller(IFileSystem fileSystem, IPathGuard guard, IReadOnlyList<string> leftoverRoots)
    {
        _fileSystem = fileSystem;
        Guard = guard;
        _leftoverRoots = leftoverRoots;
    }

    public UninstallMethod Method => UninstallMethod.VendorUninstaller;
    public IPathGuard Guard { get; }

    public AppLeftoverScanResult ScanLeftovers(InstalledApp app) =>
        LeftoverScanner.Scan(_fileSystem, Guard, app, _leftoverRoots, [app.Name]);

    /// <summary>Only ever removes the given leftover items - the app itself is already
    /// gone by the time this runs, via RunVendorUninstaller.</summary>
    public UninstallOutcome RemoveDirectly(InstalledApp app, IReadOnlyList<AppLeftoverItem> leftoverItems)
    {
        var failures = new List<CleanFailure>();
        long bytesFreed = 0;
        var itemsRemoved = 0;

        foreach (var item in leftoverItems)
        {
            if (!Guard.IsAllowed(item.FullPath, out var reason))
            {
                failures.Add(new CleanFailure(item.FullPath, $"blocked at removal-time: {reason}"));
                continue;
            }

            try
            {
                if (item.IsDirectory)
                {
                    if (_fileSystem.Directory.Exists(item.FullPath))
                    {
                        _fileSystem.Directory.Delete(item.FullPath, recursive: true);
                    }
                }
                else if (_fileSystem.File.Exists(item.FullPath))
                {
                    _fileSystem.File.Delete(item.FullPath);
                }

                bytesFreed += item.SizeBytes;
                itemsRemoved++;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                failures.Add(new CleanFailure(item.FullPath, ex.Message));
            }
        }

        return new UninstallOutcome
        {
            App = app,
            AppRemoved = false,
            LeftoverItemsRemoved = itemsRemoved,
            BytesFreed = bytesFreed,
            Failures = failures
        };
    }

    public bool RunVendorUninstaller(InstalledApp app)
    {
        var (fileName, arguments) = ParseCommandLine(app.Identifier);

        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                // Most uninstallers need UseShellExecute for their UAC elevation prompt
                // (a manifest-requested "runas") to work correctly.
                UseShellExecute = true
            });

            process?.WaitForExit();
            return process?.ExitCode == 0;
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException)
        {
            return false;
        }
    }

    private static (string FileName, string Arguments) ParseCommandLine(string commandLine)
    {
        commandLine = commandLine.Trim();

        if (commandLine.StartsWith('"'))
        {
            var closingQuote = commandLine.IndexOf('"', 1);
            if (closingQuote > 0)
            {
                var exe = commandLine[1..closingQuote];
                var args = commandLine[(closingQuote + 1)..].Trim();
                return (exe, args);
            }
        }

        var firstSpace = commandLine.IndexOf(' ');
        return firstSpace < 0
            ? (commandLine, "")
            : (commandLine[..firstSpace], commandLine[(firstSpace + 1)..].Trim());
    }
}
