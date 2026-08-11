using System.Text.Json;
using DiagClean.Core.Models;

namespace DiagClean.Cli;

public sealed class AppSettingsModel
{
    public List<string> ProtectedPaths { get; set; } = [];
    public Dictionary<string, List<string>> Presets { get; set; } = [];

    public static AppSettingsModel Load(string path)
    {
        if (!File.Exists(path))
        {
            return new AppSettingsModel();
        }

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<AppSettingsModel>(json, JsonOptions) ?? new AppSettingsModel();
        }
        catch (JsonException)
        {
            // Malformed config shouldn't crash the tool - fall back to safe defaults.
            return new AppSettingsModel();
        }
    }

    public IReadOnlyList<CleanCategory> GetPresetCategories(CleanPreset preset)
    {
        var key = preset.ToString().ToLowerInvariant();
        if (!Presets.TryGetValue(key, out var names))
        {
            return [];
        }

        return names
            .Select(n => Enum.TryParse<CleanCategory>(n, ignoreCase: true, out var c) ? c : (CleanCategory?)null)
            .Where(c => c.HasValue)
            .Select(c => c!.Value)
            .ToList();
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };
}
