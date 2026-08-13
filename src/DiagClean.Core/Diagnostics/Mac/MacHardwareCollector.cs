using System.Runtime.Versioning;
using DiagClean.Core.Models;
using DiagClean.Core.Shell;

namespace DiagClean.Core.Diagnostics.Mac;

[SupportedOSPlatform("macos")]
public sealed class MacHardwareCollector : IHardwareCollector
{
    public HardwareInfo Collect()
    {
        var cpuName = ReadSysctlString("machdep.cpu.brand_string");
        var cores = ReadSysctlInt("hw.physicalcpu");
        var logical = ReadSysctlInt("hw.logicalcpu");
        var memBytes = ReadSysctlLong("hw.memsize");

        var hardwareInfo = ShellRunner.Run("system_profiler", ["SPHardwareDataType"]) ?? "";
        var modelName = ExtractField(hardwareInfo, "Model Name");
        var modelIdentifier = ExtractField(hardwareInfo, "Model Identifier");
        var chip = ExtractField(hardwareInfo, "Chip");
        var firmware = ExtractField(hardwareInfo, "System Firmware Version");
        if (string.IsNullOrEmpty(firmware))
        {
            firmware = ExtractField(hardwareInfo, "Boot ROM Version");
        }

        var displayInfo = ShellRunner.Run("system_profiler", ["SPDisplaysDataType"]) ?? "";
        var gpus = ExtractAllFields(displayInfo, "Chipset Model");
        if (gpus.Count == 0 && !string.IsNullOrEmpty(chip))
        {
            // Apple Silicon's integrated GPU doesn't always get its own "Chipset Model"
            // line - the SoC name from SPHardwareDataType is the best available label.
            gpus = [$"{chip} (Integrated)"];
        }

        return new HardwareInfo
        {
            CpuName = string.IsNullOrEmpty(cpuName) ? chip : cpuName,
            CpuCores = cores,
            CpuLogicalProcessors = logical,
            TotalRamGb = Math.Round(memBytes / (1024d * 1024 * 1024), 1),
            MotherboardManufacturer = "Apple",
            MotherboardModel = string.IsNullOrEmpty(modelName) ? modelIdentifier : $"{modelName} ({modelIdentifier})",
            BiosVersion = firmware,
            GpuNames = gpus
        };
    }

    private static string ReadSysctlString(string key) => ShellRunner.Run("sysctl", ["-n", key])?.Trim() ?? "";

    private static int ReadSysctlInt(string key) =>
        int.TryParse(ReadSysctlString(key), out var value) ? value : 0;

    private static long ReadSysctlLong(string key) =>
        long.TryParse(ReadSysctlString(key), out var value) ? value : 0;

    internal static string ExtractField(string text, string label)
    {
        foreach (var rawLine in text.Split('\n'))
        {
            var line = rawLine.Trim();
            if (line.StartsWith(label + ":", StringComparison.OrdinalIgnoreCase))
            {
                return line[(label.Length + 1)..].Trim();
            }
        }

        return "";
    }

    private static List<string> ExtractAllFields(string text, string label)
    {
        var results = new List<string>();
        foreach (var rawLine in text.Split('\n'))
        {
            var line = rawLine.Trim();
            if (line.StartsWith(label + ":", StringComparison.OrdinalIgnoreCase))
            {
                results.Add(line[(label.Length + 1)..].Trim());
            }
        }

        return results;
    }
}
