using System.Runtime.Versioning;
using DiagClean.Core.Models;
using Microsoft.Win32;

namespace DiagClean.Core.Diagnostics;

[SupportedOSPlatform("windows")]
public sealed class SoftwareInventoryCollector : ISoftwareInventoryCollector
{
    private static readonly (RegistryHive Hive, string SubKey)[] Roots =
    [
        (RegistryHive.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        (RegistryHive.LocalMachine, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
        (RegistryHive.CurrentUser, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
    ];

    public IReadOnlyList<InstalledSoftware> Collect()
    {
        var results = new List<InstalledSoftware>();
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

                    // SystemComponent entries are OS-internal pieces, not user-installed apps.
                    if (entry.GetValue("SystemComponent") is int sc && sc == 1)
                    {
                        continue;
                    }

                    if (!seen.Add(displayName))
                    {
                        continue;
                    }

                    results.Add(new InstalledSoftware
                    {
                        Name = displayName,
                        Version = entry.GetValue("DisplayVersion") as string ?? "",
                        Publisher = entry.GetValue("Publisher") as string ?? "",
                        InstallDate = ParseInstallDate(entry.GetValue("InstallDate") as string)
                    });
                }
            }
            catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException)
            {
                // Insufficient rights to read this hive/subkey on this machine - skip just this
                // root and keep the results already gathered from the others. Modern .NET
                // registry APIs throw UnauthorizedAccessException for access-denied far more
                // often than the legacy SecurityException, so both must be caught here -
                // otherwise one restricted hive (common under corporate GPO) would discard
                // every result already collected from the roots processed before it.
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
