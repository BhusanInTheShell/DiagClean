using System.Runtime.Versioning;
using DiagClean.Core.Models;
using Microsoft.Win32;

namespace DiagClean.Core.Uninstall.Windows;

/// <summary>
/// Same registry roots as Diagnostics/SoftwareInventoryCollector, but only entries with
/// a usable UninstallString are listed - Uninstall needs something to actually launch,
/// unlike the diagnostic inventory which just reports what's installed.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WindowsAppLister : IAppLister
{
    private static readonly (RegistryHive Hive, string SubKey)[] Roots =
    [
        (RegistryHive.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        (RegistryHive.LocalMachine, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
        (RegistryHive.CurrentUser, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
    ];

    public IReadOnlyList<InstalledApp> ListApps()
    {
        var results = new List<InstalledApp>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var (hive, subKey) in Roots)
        {
            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Default);
                using var uninstallKey = baseKey.OpenSubKey(subKey);
                if (uninstallKey is null)
                {
                    continue;
                }

                foreach (var name in uninstallKey.GetSubKeyNames())
                {
                    using var entry = uninstallKey.OpenSubKey(name);
                    if (entry is null)
                    {
                        continue;
                    }

                    var displayName = entry.GetValue("DisplayName") as string;
                    if (string.IsNullOrWhiteSpace(displayName))
                    {
                        continue;
                    }

                    if (entry.GetValue("SystemComponent") is int sc && sc == 1)
                    {
                        continue;
                    }

                    var uninstallString = entry.GetValue("UninstallString") as string;
                    if (string.IsNullOrWhiteSpace(uninstallString))
                    {
                        // Nothing DiagClean can launch for this entry - leave it for
                        // "Apps & Features" to handle rather than list a dead end.
                        continue;
                    }

                    if (!seen.Add(displayName))
                    {
                        continue;
                    }

                    var sizeKb = entry.GetValue("EstimatedSize") is int kb ? kb : 0;

                    results.Add(new InstalledApp
                    {
                        Name = displayName,
                        Identifier = uninstallString,
                        InstallPath = entry.GetValue("InstallLocation") as string ?? "",
                        Version = entry.GetValue("DisplayVersion") as string ?? "",
                        Publisher = entry.GetValue("Publisher") as string ?? "",
                        SizeBytes = sizeKb * 1024L,
                        LastModified = ParseInstallDate(entry.GetValue("InstallDate") as string)
                    });
                }
            }
            catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException)
            {
                // Same reasoning as SoftwareInventoryCollector - skip just this root.
            }
        }

        return results;
    }

    private static DateOnly? ParseInstallDate(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || raw.Length != 8)
        {
            return null;
        }

        return DateOnly.TryParseExact(raw, "yyyyMMdd", out var date) ? date : null;
    }
}
