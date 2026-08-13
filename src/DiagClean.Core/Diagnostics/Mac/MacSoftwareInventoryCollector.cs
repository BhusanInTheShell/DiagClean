using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.RegularExpressions;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Diagnostics.Mac;

/// <summary>
/// system_profiler SPApplicationsDataType walks and verifies every app bundle's code
/// signature, which can take significantly longer than any other collector here on a
/// Mac with a lot of installed software - an accepted tradeoff since it's the only
/// built-in source for a complete application inventory without depending on Homebrew
/// or another package manager being present.
/// </summary>
[SupportedOSPlatform("macos")]
public sealed class MacSoftwareInventoryCollector : ISoftwareInventoryCollector
{
    // Matches the certificate common-name pattern in "signed_by": e.g.
    // "Developer ID Application: Ascensio System SIA (2WH24U26GJ)" -> "Ascensio System SIA".
    private static readonly Regex DeveloperIdPattern = new(
        @"Developer ID Application:\s*(.+?)\s*\([A-Z0-9]+\)", RegexOptions.Compiled);

    public IReadOnlyList<InstalledSoftware> Collect()
    {
        var output = ShellRunner.Run(
            "system_profiler",
            ["SPApplicationsDataType", "-json"],
            timeout: TimeSpan.FromSeconds(45));

        if (output is null)
        {
            return [];
        }

        try
        {
            using var doc = JsonDocument.Parse(output);
            if (!doc.RootElement.TryGetProperty("SPApplicationsDataType", out var apps))
            {
                return [];
            }

            var results = new List<InstalledSoftware>();
            foreach (var app in apps.EnumerateArray())
            {
                var name = app.TryGetProperty("_name", out var nameProp) ? nameProp.GetString() : null;
                if (string.IsNullOrWhiteSpace(name))
                {
                    continue;
                }

                var version = app.TryGetProperty("version", out var versionProp) ? versionProp.GetString() ?? "" : "";
                var obtainedFrom = app.TryGetProperty("obtained_from", out var obtProp) ? obtProp.GetString() ?? "" : "";
                var installDate = app.TryGetProperty("lastModified", out var dateProp) &&
                                   DateTimeOffset.TryParse(dateProp.GetString(), out var dt)
                    ? DateOnly.FromDateTime(dt.UtcDateTime)
                    : (DateOnly?)null;

                results.Add(new InstalledSoftware
                {
                    Name = name,
                    Version = version,
                    Publisher = ResolvePublisher(obtainedFrom, app),
                    InstallDate = installDate
                });
            }

            return results;
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static string ResolvePublisher(string obtainedFrom, JsonElement app)
    {
        if (obtainedFrom == "identified_developer" &&
            app.TryGetProperty("signed_by", out var signedBy) &&
            signedBy.ValueKind == JsonValueKind.Array &&
            signedBy.GetArrayLength() > 0)
        {
            var certName = signedBy[0].GetString() ?? "";
            var match = DeveloperIdPattern.Match(certName);
            if (match.Success)
            {
                return match.Groups[1].Value;
            }
        }

        return obtainedFrom switch
        {
            "apple" => "Apple",
            "mac_app_store" or "ios_app_store" => "App Store",
            "identified_developer" => "Identified Developer",
            _ => "Unknown"
        };
    }
}
